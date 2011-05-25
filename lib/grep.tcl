class grep {

# widgets
field w
field w_vpane
field w_entry
field w_files
field w_cnts
field w_grep
field w_lnos
field grep_lno
field grep_nl
field next_nl_tag

field ui_cnts_width 3
field ui_cnts_width_max
field ui_files_cols
field ui_lnos_width 5
field ui_lnos_width_max
field ui_grep_cols

field matched_files_n 0
field matched_files_total_cnt 0
field matched_files_label {}
field file_list
field current_path {}
field previous_path {}
field current_path_label {}
field patterns [list]
field patterns_pos -1
field busy 0
field current_fd

field first_match_line 0

field buf_rgl {}

constructor embed {i_w} {

	set w $i_w
	_init $this

	return $this
}

constructor new {args} {

	make_toplevel top w
	wm title $top "Git-Gui: Grep"

	_init $this

	bind $top <Control-Key-r> [cb grep]
	bind $top <Control-Key-R> [cb grep]
	bind $top <Control-Key-h> [cb grep_from_selection]
	bind $top <Control-Key-H> [cb grep_from_selection]

	set font_w [font measure font_diff "0"]

	set req_w [winfo reqwidth  $top]
	set req_h [winfo reqheight $top]
	set scr_w [expr {[winfo screenwidth $top] - 40}]
	set scr_h [expr {[winfo screenheight $top] - 120}]
	set opt_w [expr {$font_w * (80 + 32)}]
	if {$req_w < $opt_w} {set req_w $opt_w}
	if {$req_w > $scr_w} {set req_w $scr_w}
	set opt_h [expr {$scr_h*1/2}]
	if {$req_h < $scr_h} {set req_h $scr_h}
	if {$req_h > $opt_h} {set req_h $opt_h}
	set g "${req_w}x${req_h}"
	wm geometry $top $g
	update

	wm protocol $top WM_DELETE_WINDOW "destroy $top"
	bind $top <Destroy> [cb _handle_destroy %W]

	if {[llength $args] > 0} {
		set pattern {}
		foreach arg $args {
			if {$pattern ne {}} {
				append pattern { }
			}
			if {[regexp {[ \t\r\n'"$?*]} $arg]} {
				#"
				set arg [sq $arg]
			}
			append pattern $arg
		}
		grep $this $pattern
	}
}

method _init {} {

	# base path for all grep widgets
	set w_vpane $w.v
	set w_entry $w.entry
	set w_files $w_vpane.f.text
	set w_cnts  $w_vpane.f.cnts
	set w_grep  $w_vpane.o.text
	set w_lnos  $w_vpane.o.lnos

	ttk::panedwindow $w_vpane -orient horizontal

	entry $w_entry \
		-font TkDefaultFont \
		-selectbackground darkgray \
		-disabledforeground white \
		-disabledbackground blue \
		-validate key \
		-validatecommand [cb _reset_errstatus] \
		-takefocus [cb _always_takefocus]

	pack $w_vpane -side top -fill both -expand 1
	pack $w_entry -side bottom -fill x

	textframe $w_vpane.f -borderwidth 0
	textframe $w_vpane.o -borderwidth 0
	$w_vpane add $w_vpane.f -weight 0
	$w_vpane add $w_vpane.o -weight 1

	## list of files with matches

	ttk::label $w_vpane.f.title \
		-style Color.TLabel \
		-textvariable @matched_files_label \
		-background lightsalmon \
		-foreground black

	text $w_files \
		-background white \
		-foreground black \
		-borderwidth 0 \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-state disabled \
		-wrap none \
		-width 20 \
		-height 10 \
		-xscrollcommand [list $w_vpane.f.sbx set]
	$w_files tag conf default -lmargin1 5 -rmargin 1

	text $w_cnts \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-background grey95 \
		-foreground black \
		-borderwidth 0 \
		-width [expr $ui_cnts_width + 1] \
		-height 10 \
		-wrap none \
		-state disabled
	$w_cnts tag conf count -justify right -lmargin1 2 -rmargin 3 -foreground red

	set ui_files_cols [list $w_files $w_cnts]

	# simulate linespacing, as if it has an icon like the index/worktree
	# lists
	set fn [$w_cnts cget -font]
	set ls [font metrics $fn -linespace]
	if {$ls < 17} {
		set d [expr 17 - $ls]
		set b [expr $d / 2]
		set t $b
		if {[expr $b + $t] != $d} {
			incr b
		}
		foreach i $ui_files_cols {
			$i configure -spacing1 $t -spacing3 $b
		}
	}

	ttk::scrollbar $w_vpane.f.sbx \
		-orient h \
		-command [list $w_files xview]

	ttk::scrollbar $w_vpane.f.sby \
		-orient v \
		-command [list scrollbar2many $ui_files_cols yview]

	grid configure $w_vpane.f.title \
		-column 0 \
		-columnspan 3 \
		-sticky we

	grid $w_files $w_cnts $w_vpane.f.sby -sticky nsew

	grid configure $w_vpane.f.sbx \
		-column 0 \
		-columnspan 3 \
		-sticky we

	grid columnconfigure $w_vpane.f \
		0 \
		-weight 1
	grid rowconfigure $w_vpane.f \
		1 \
		-weight 1

	foreach i $ui_files_cols {
		rmsel_tag $i

		$i conf -cursor arrow
		$i conf -yscrollcommand \
			"[list many2scrollbar $ui_files_cols yview $w_vpane.f.sby]"

		bind $i <Button-1>        "[cb _select_from_list %x %y]; break"
		bind $i <ButtonRelease-2> "[cb _select_from_list %x %y [cb _open_first_match]]; break"
	}

	## grep output from one file

	ttk::label $w_vpane.o.title \
		-style Color.TLabel \
		-textvariable @current_path_label \
		-background gold \
		-foreground black \
		-justify right \
		-anchor e

	set ctxm $w_vpane.o.title.ctxm
	menu $ctxm -tearoff 0
	$ctxm add command \
		-label [mc Copy] \
		-command [cb _copy_path]
	bind_button3 $w_vpane.o.title "tk_popup $ctxm %X %Y"

	text $w_lnos \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-background grey95 \
		-foreground black \
		-borderwidth 0 \
		-width [expr $ui_lnos_width + 1] \
		-height 10 \
		-wrap none \
		-state disabled \
		-font font_diff
	$w_lnos tag conf linenumber -justify right -rmargin 5
	$w_lnos tag conf linenumbermatch -justify right -rmargin 5 -foreground red

	text $w_grep \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-background white \
		-foreground black \
		-borderwidth 0 \
		-width 80 \
		-height 10 \
		-wrap none \
		-xscrollcommand [list $w_vpane.o.sbx set] \
		-state disabled \
		-font font_diff

	$w_grep tag conf hunksep -background grey95
	$w_grep tag conf d_info -foreground blue -font font_diffbold

	foreach {n c} {0 black 1 red 2 green4 3 yellow4 4 blue4 5 magenta4 6 cyan4 7 grey60} {
		$w_grep tag configure clr4$n -background $c
		$w_grep tag configure clri4$n -foreground $c
		$w_grep tag configure clr3$n -foreground $c
		$w_grep tag configure clri3$n -background $c
	}
	$w_grep tag configure clr1 -font font_diffbold
	$w_grep tag configure clr4 -underline 1

	set ui_grep_cols [list $w_lnos $w_grep]

	delegate_sel_to $w_grep [list $w_lnos]

	ttk::scrollbar $w_vpane.o.sbx \
		-orient h \
		-command [list $w_grep xview]

	ttk::scrollbar $w_vpane.o.sby \
		-orient v \
		-command [list scrollbar2many $ui_grep_cols yview]

	grid configure $w_vpane.o.title \
		-column 0 \
		-columnspan 3 \
		-sticky ew

	grid $w_lnos $w_grep $w_vpane.o.sby -sticky nsew

	grid configure $w_vpane.o.sbx \
		-column 0 \
		-columnspan 3 \
		-sticky we

	grid columnconfigure $w_vpane.o \
		1 \
		-weight 1
	grid rowconfigure $w_vpane.o \
		1 \
		-weight 1

	rmsel_tag $w_lnos
	foreach i $ui_grep_cols {
		$i tag raise sel

		$i conf -yscrollcommand \
			"[list many2scrollbar $ui_grep_cols yview $w_vpane.o.sby]"

		bind $i <ButtonRelease-2> "[cb _open_from_grep %x %y]"
	}

	foreach i [list $w $w_files $w_cnts $w_lnos $w_grep $w_entry] {

		# grep history
		bind $i <Alt-Key-Left>  "[cb grep_prev]; break"
		bind $i <Alt-Key-Right> "[cb grep_next]; break"

		# scoll of file list
		bind $i <Up>            "[cb _files_scroll_line -1]; break"
		bind $i <Down>          "[cb _files_scroll_line  1]; break"
		bind $i <Key-Prior>     "[cb _files_scroll_page -1]; break"
		bind $i <Key-Next>      "[cb _files_scroll_page  1]; break"

		# scroll of grep result
		bind $i <Alt-Key-Up>    "[cb _grep_scroll yview -1 units]; break"
		bind $i <Alt-Key-Down>  "[cb _grep_scroll yview  1 units]; break"
		bind $i <Alt-Prior>     "[cb _grep_scroll yview -1 pages]; break"
		bind $i <Alt-Next>      "[cb _grep_scroll yview  1 pages]; break"
	}

	foreach i [list $w $w_files $w_cnts $w_lnos $w_grep] {
		bind $i <Left>         break
		bind $i <Right>        break
		bind $i <Return>       "[cb _open_first_match]; break"
	}

	bind $w_entry <Return>        [cb _grep_from_entry]
	bind $w_entry <Shift-Return>  "[cb _open_first_match]; break"
	bind $w_entry <Key-Left>      [cb _reset_errstatus]
	bind $w_entry <Key-Right>     [cb _reset_errstatus]
	bind $w_entry <Control-Key-c> [cb _cancel]
	bind $w_entry <Visibility>    [list focus $w_entry]

	# matched_files_n needs to be set last
	trace add variable matched_files_n write [cb _update_matched_files_label]
	set matched_files_total_cnt 0
	set matched_files_n 0

	trace add variable current_path write [cb _update_path_label]
	set current_path {}

	set patterns [list]
}

method _clear_grep {} {
	foreach i $ui_grep_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_lnos conf -width [expr $ui_lnos_width + 1]

	set grep_nl ""
	set grep_lno 1
	set next_nl_tag {}

	set first_match_line 0

	set previous_path $current_path
	set current_path {}
}

method grep {{pattern {}}} {
	if {$busy} return
	set busy 1

	$w_entry delete 0 end

	set file_list [list]
	foreach i $ui_files_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_cnts conf -width [expr $ui_cnts_width + 1]
	set ui_cnts_width_max $ui_cnts_width
	set matched_files_total_cnt 0
	set matched_files_n 0

	_clear_grep $this

	set buf_rgl {}

	if {$pattern ne {}} {
		lappend patterns "$pattern"
		set patterns_pos [expr [llength $patterns] - 1]
	}

	if {$patterns_pos == -1} {
		set busy 0
		return
	}

	set pattern [lindex $patterns $patterns_pos]

	$w_entry insert 0 $pattern
	$w_entry conf -state disabled

	ui_status "Grep for matching files..."
	set cmd [list | [shellpath] -c "git grep --recurse-submodules -c -z $pattern"]
	if {[catch {set current_fd [open $cmd r]} err]} {
		$w_entry conf -state normal -background lightsalmon
		set busy 0

		tk_messageBox \
			-icon error \
			-type ok \
			-title {git-gui: grep: fatal error} \
			-message $err

		return
	}
	fconfigure $current_fd -eofchar {}
	fconfigure $current_fd \
		-blocking 0 \
		-buffering full \
		-buffersize 512 \
		-translation binary
	fileevent $current_fd readable [cb _do_read]
}

method _do_read {} {
	append buf_rgl [read $current_fd]
	set c 0
	set n [string length $buf_rgl]

	foreach i $ui_files_cols {$i conf -state normal}
	while {$c < $n} {
		# find the \0 after a path
		set zb [string first "\0" $buf_rgl $c]
		if {$zb == -1} break
		set path  [string range $buf_rgl $c [expr {$zb - 1}]]
		incr zb

		# find the newline after the count
		set nl [string first "\n" $buf_rgl $zb]
		if {$nl == -1} break
		set cnt [string range $buf_rgl $zb [expr {$nl - 1}]]
		incr nl

		set path [encoding convertfrom $path]
		lappend file_list $path

		$w_cnts insert end "$cnt\n" count
		set cnt_len [string length $cnt]
		if {$ui_cnts_width_max < $cnt_len} {
			set ui_cnts_width_max $cnt_len
		}
		$w_files insert end "[escape_path $path]\n" default
		incr matched_files_total_cnt $cnt
		incr matched_files_n

		set c $nl
	}
	foreach i $ui_files_cols {$i conf -state disabled}

	if {$c < $n} {
		set buf_rgl [string range $buf_rgl $c end]
	} else {
		set buf_rgl {}
	}

	fconfigure $current_fd -blocking 1
	if {![eof $current_fd]} {
		fconfigure $current_fd -blocking 0
		return
	}

	if {[catch {close $current_fd} err]} {
		$w_entry conf -state normal -background lightsalmon
	} else {
		$w_entry conf -state normal -background lightgreen
	}

	# remove trailing newline
	foreach i $ui_files_cols {
		$i conf -state normal
		$i delete "end -1 char"
		$i conf -state disabled
	}
	$w_cnts conf -width [expr $ui_cnts_width_max + 1]

	set busy 0
	ui_ready

	if {[llength $file_list] eq 0} {
		return
	}

	set file_index -1
	if {$previous_path ne {}} {
		set file_index [lsearch -exact $file_list $previous_path]
	}
	if {$file_index == -1} {
		set file_index 0
	}
	# lines starting with 1, so add 1 more line to the zero based file_index
	set line [expr {$file_index + 1}]
	foreach i $ui_files_cols {
		$i tag add in_sel "$line.0" "$line.0 + 1 line"
	}
	_show_file $this [lindex $file_list $file_index]
} ifdeleted { catch {close $current_fd} }

method _show_file {path {after {}}} {
	set cmd [list | [shellpath] -c "git grep --recurse-submodules --color -h -n -p -3 [lindex $patterns $patterns_pos] -- [sq [encoding convertto $path]]"]

	_clear_grep $this
	set ui_lnos_width_max $ui_lnos_width

	ui_status "Grepping [escape_path $path]..."
	set current_path $path

	if {[catch {set fd [open $cmd r]} err]} {
		tk_messageBox \
			-icon error \
			-type ok \
			-title {gui-grep: fatal error} \
			-message $err
		set current_path {}
		ui_status "Grepping of [escape_path $path] failed..."
		unset fd
		return
	}
	fconfigure $fd -eofchar {}
	fconfigure $fd \
		-blocking 0 \
		-encoding [get_path_encoding $path] \
		-buffering full \
		-buffersize 512 \
		-translation lf
	fileevent $fd readable [cb _file_read $fd $path $after]
}

method _file_read {fd path after} {
	foreach i $ui_grep_cols {$i conf -state normal}

	while {[gets $fd line] >= 0} {

		set nl_tag $next_nl_tag
		set next_nl_tag {}

		if {[string match {Binary file * matches} $line]} {
			$w_lnos insert end "${grep_nl}*" linenumber
			$w_grep insert end "${grep_nl}Binary file matches" d_info
			set grep_nl "\n"
			incr grep_lno
			continue
		}

		set lno_tag linenumber
		# catch hunk sep --
		if {[regexp {^(?:\033\[(?:(?:\d+;)*\d+)m)?--(?:\033\[m)?} $line]} {
			set lno "--"
			set mline {}
			set markup [list]
			set next_nl_tag hunksep
		} else {
			# remove any color from lno and sep
			regexp {^(?:\033\[(?:(?:\d+;)*\d+)m)?(\d+)(?:\033\[m)?(?:\033\[(?:(?:\d+;)*\d+)m)?([-:=])(?:\033\[m)?(.*)$} $line all lno line_type mline
			foreach {mline markup} [parse_color_line $mline] break
			set mline [string map {\033 ^} $mline]
			regsub {\r$} $mline {} mline
			if {$line_type eq {:}} {
				set lno_tag linenumbermatch
				if {$first_match_line eq 0} {
					set first_match_line $lno
				}
			}
		}

		set mark $grep_lno.0

		$w_lnos insert end "$grep_nl$lno" $lno_tag
		set lno_len [string length $lno]
		if {$ui_lnos_width_max < $lno_len} {
			set ui_lnos_width_max $lno_len
		}
		$w_grep insert end "$grep_nl" $nl_tag
		$w_grep insert end "$mline"
		set grep_nl "\n"
		incr grep_lno

		foreach {posbegin colbegin posend colend} $markup {
			set prefix clr
			foreach style [lsort -integer [split $colbegin ";"]] {
				if {$style eq "7"} {append prefix i; continue}
				# ignore bold (1), because it doesn't buy us anything
				if {$style != 4
				    && ($style < 30 || $style > 37)
				    && ($style < 40 || $style > 47)} {
					continue
				}
				set a "$mark + $posbegin chars"
				set b "$mark + $posend chars"
				catch {$w_grep tag add $prefix$style $a $b}
			}
		}
	}

	if {[eof $fd]} {
		close $fd

		#update line number column width
		$w_lnos conf -width [expr $ui_lnos_width_max + 1]

		ui_ready

		if {$after ne {}} {
			eval $after
		}
	}

	foreach i $ui_grep_cols {$i conf -state disabled}
} ifdeleted { catch {close $fd} }

method _select_from_list {x y {after {}}} {
	focus $w_files

	set lno [lindex [split [$w_files index @0,$y] .] 0]
	set path [lindex $file_list [expr {$lno - 1}]]
	if {$path eq {}} {
		return
	}

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
		$i tag add in_sel $lno.0 "$lno.0 + 1 line"
	}

	if {$path eq $current_path} {
		if {$after ne {}} {
			eval $after
		}
		return
	}

	_show_file $this $path $after
}

method _open_from_grep {x y} {
	if {$current_path eq {}} {
		return
	}

	set lno {}
	set wlno [$w_lnos search -regexp {^[[:digit:]]+$} "@0,$y linestart" end]
	if {$wlno eq {}} {
		set wlno [$w_lnos search -backwards -regexp {^[[:digit:]]+$} "@0,$y linestart" 1.0]
	}
	if {$wlno ne {}} {
		set lno [$w_lnos get "$wlno" "$wlno lineend"]
	}

	open_in_git_editor $current_path $lno
}

method _open_first_match {} {
	if {$current_path eq {} || $first_match_line == 0} {
		return
	}
	open_in_git_editor $current_path $first_match_line
}

method grep_from_selection {} {
	if {[catch {set expr [selection get -selection PRIMARY -type STRING]}]} {
		return
	}
	if {$expr eq {}} {
		return
	}
	set expr [sq $expr]

	grep $this "-F -e $expr"
}

method _grep_from_entry {} {
	set expr [$w_entry get]

	# open selected file if we didn't changed the pattern
	if {$patterns_pos != -1 && $expr eq [lindex $patterns $patterns_pos]} {
		_open_first_match $this
	} else {
		grep $this $expr
	}
}

method grep_prev {} {
	_reset_errstatus $this
	if {$patterns_pos > 0} {
		incr patterns_pos -1
		grep $this
	}
}

method grep_next {} {
	_reset_errstatus $this
	if {[expr {$patterns_pos + 1}] < [llength $patterns]} {
		incr patterns_pos
		grep $this
	}
}

method _update_path_label {args} {
	if {$current_path eq {}} {
		set current_path_label "No file matched."
	} else {
		set current_path_label "File: [escape_path $current_path]"
	}
}

method _update_matched_files_label {args} {
	if {$matched_files_n == 0 || $matched_files_total_cnt == 0} {
		set matched_files_label "Matched Files"
	} else {
		set matched_files_label "Matched Files: $matched_files_n ($matched_files_total_cnt)"
	}
}

method _files_scroll_line {dir} {
	if {$busy} return

	if {[catch {$w_files index in_sel.first}]} {
		return
	}

	set lno [lindex [split [$w_files index in_sel.first] .] 0]
	incr lno $dir

	set path [lindex $file_list [expr {$lno - 1}]]
	if {$path eq {}} {
		return
	}

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
		$i tag add in_sel $lno.0 "$lno.0 + 1 line"
	}
	$w_files see $lno.0

	_show_file $this $path
}

method _files_scroll_page {dir} {
	if {$busy} return

	set page [expr {
		int(
		  ceil(
		    ([lindex [$w_files yview] 1] - [lindex [$w_files yview] 0])
		    * [llength $file_list]
		  )
		)}]
	set lno [expr "[lindex [split [$w_files index in_sel.first] .] 0] + $dir * $page"]
	if {1 > $lno} {set lno 1}
	if {$lno > [llength $file_list]} {set lno [llength $file_list]}

	set path [lindex $file_list [expr {$lno - 1}]]
	if {$path eq {}} {
		return
	}

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
		$i tag add in_sel $lno.0 "$lno.0 + 1 line"
	}
	$w_files see $lno.0

	_show_file $this $path
}

method _grep_scroll {v a u} {
	$w_grep $v scroll $a $u
}

method _copy_path {} {
	clipboard clear
	clipboard append \
		-format STRING \
		-type STRING \
		-- $current_path
}

method _reset_errstatus {} {
	$w_entry conf -background white
	return 1
}

method _cancel {} {
	if {$busy} {
		set busy 0
		catch {close $current_fd}
		$w_entry conf -state normal -background lightsalmon
		foreach i $ui_files_cols {
			$i conf -state normal
			$i delete "end -1 char"
			$i conf -state disabled
		}
	}
}

method _always_takefocus {w} {
	return 1
}

method _handle_destroy {win} {
	if {$win eq $w} {
		delete_this
	}
}

method link_vpane {vpane} {
	bind $w_vpane <Map> [cb _on_pane_mapped $vpane]
}

method _on_pane_mapped {master_vpane} {
	if {$::use_ttk} {
		after idle [list after idle [list $w_vpane sashpos 0 [$master_vpane sashpos 0]]]
	} else {
		after idle [list after idle \
			[list $w_vpane sash place 0 \
				[lindex [$master_vpane sash coord 0] 0] \
				[lindex [$w_vpane      sash coord 0] 1]]]
	}
}

method reorder_bindtags {} {
	foreach i [list $w $w_files $w_cnts $w_lnos $w_grep $w_entry] {
		bindtags $i [list all $i [winfo class $i] .]
	}
}

}
