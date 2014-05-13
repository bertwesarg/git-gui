class build {

# widgets
field w
field w_hpane
field w_vpane

field w_files
field w_diags
field w_errs
field ui_errs_width 3
field ui_errs_width_max
field w_warns
field ui_warns_width 3
field ui_warns_width_max
field ui_files_cols

field w_lnos
field ui_lnos_width 5
field ui_lnos_width_max
field w_hits
field ui_hits_cols

field w_indicator
field m_configs
field w_output
field ui_finder
field w_entry

field state
field state_change_cb

field file_list
field current_file_list
field file_info
field diag_list
field current_diag
field current_path {}
field current_path_label {}
field current_path_lno_hits
field file_list_needs_update 0
field busy 0
field file_list_busy 0
field hits_busy 0
field current_fd
field vpath {.}
field dir_stack {}
field run_nl {}
field hits_nl {}

field shell
field envmods
field configmods
field selected_configs
field buildconfig_config
field buildconfig_menu_id 0

# record and history
field current_cmd {}
field current_cmd_label {}
field build_ref refs/builds/default
field build_index
field output_hash_pipe
field output_hash_out
# static tree entries (cwd, environ)
field static_build_tree
# per run tree entries (output, exit status, worktree)
field build_tree
field build_start
field build_start_s
field build_end
field build_run_s 0
field build_timer
field cmd_history
field cmd_history_pos 0
field build_history
field build_history_pos -1

constructor embed {i_w {i_vpath {}} {i_ref {}} {i_shell {}} {i_envmods {}} {i_configs {}} {i_state_change_cb {}}} {

	set w $i_w

	if {[catch {_init $this $i_vpath $i_ref $i_shell $i_envmods $i_configs $i_state_change_cb} err]} {
		return -code error $err
	}

	return $this
}

method _init {i_vpath i_ref i_shell i_envmods i_configs i_state_change_cb} {
	global env

	if {$i_vpath ne {}} {
		set vpath $i_vpath
	}

	if {$i_ref ne {}} {
		switch -glob $i_ref {
		*/
			{return -code error "Invalid build ref ending in /: $i_ref"}
		refs/builds/*
			{set build_ref $i_ref}
		refs/*
			{return -code error "Invalid build ref: $i_ref"}
		builds/*
			{set build_ref refs/$i_ref}
		*
			{set build_ref refs/builds/$i_ref}
		}
	}
	set build_name [string range $build_ref [string length {refs/}] end]
	if {[string length $::GIT_NAMESPACE]} {
		set build_ref "refs/namespaces/[join [split $::GIT_NAMESPACE {/}] {/refs/namespaces/}]/$build_ref"
		set build_name "$::GIT_NAMESPACE/$build_name"
	}
	set build_index $::GIT_INDEX_FILE.[string map {/ .} $build_name].[pid]

	if {$i_shell eq {}} {
		set shell [shellpath]
	} else {
		set shell $i_shell
	}

	set envmods [list]
	foreach mod $i_envmods {
		if {[regexp {^([A-Za-z0-9_]+)\s*((?:[-+%].?)?=)\s*(.*)$} $mod match name op value]} {
			lappend envmods $name $op $value
		} elseif {[regexp {^!([A-Za-z0-9_]+)$} $mod match name]} {
			lappend envmods $name ! {}
		} else {
			tk_messageBox \
				-icon warning \
				-type ok \
				-title {git-gui: build: invalid env mod} \
				-message "Invalid env mod command: $mod"
		}
	}

	set configmods $i_configs
	array set selected_configs {}

	set state_change_cb $i_state_change_cb

	# base path for all grep widgets
	set w_hpane $w.h
	set w_vpane $w_hpane.v

	set w_files $w_vpane.f.l
	set w_diags $w_vpane.f.t.k
	set w_errs  $w_vpane.f.e
	set w_warns $w_vpane.f.w

	set w_lnos  $w_vpane.o.l
	set w_hits  $w_vpane.o.d

	set w_indicator $w_hpane.f.l
	set m_configs   $w_hpane.f.l.c
	set w_output    $w_hpane.f.o
	set w_entry     $w_hpane.f.e

	ttk::panedwindow $w_hpane -orient vertical
	ttk::panedwindow $w_vpane -orient horizontal

	ttk::frame $w_hpane.f -borderwidth 0
	pack $w_hpane -side top -fill both -expand 1

	$w_hpane add $w_vpane   -weight 0
	$w_hpane add $w_hpane.f -weight 1

	ttk::frame $w_vpane.f -borderwidth 0
	ttk::frame $w_vpane.o -borderwidth 0
	$w_vpane add $w_vpane.f -weight 0
	$w_vpane add $w_vpane.o -weight 1

	## list of files with errors and warnings

	ttk::frame $w_vpane.f.t -borderwidth 0

	ttk::label $w_vpane.f.t.l \
		-style Color.TLabel \
		-text "Diagnosed Files" \
		-background lightsalmon \
		-foreground black

	set diag_list [list "All"]

	ttk::combobox $w_diags \
		-style Color.TCombobox \
		-state readonly \
		-takefocus 0 \
		-justify right \
		-exportselection false \
		-background lightsalmon \
		-values $diag_list

	grid configure $w_vpane.f.t.l $w_diags \
		-sticky nsew

	grid columnconfigure $w_vpane.f.t \
		0 \
		-weight 1

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

	text $w_errs \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-background grey95 \
		-foreground black \
		-borderwidth 0 \
		-width [expr $ui_errs_width + 1] \
		-height 10 \
		-wrap none \
		-state disabled
	$w_errs tag conf count -justify right -lmargin1 2 -rmargin 3 -foreground red

	text $w_warns \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-background grey90 \
		-foreground black \
		-borderwidth 0 \
		-width [expr $ui_warns_width + 1] \
		-height 10 \
		-wrap none \
		-state disabled
	$w_warns tag conf count -justify right -lmargin1 2 -rmargin 3 -foreground orange

	set ui_files_cols [list $w_files $w_errs $w_warns]

	# simulate linespacing, as if it has an icon like the index/worktree
	# lists
	set fn [$w_files cget -font]
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

	grid configure $w_vpane.f.t \
		-column 0 \
		-columnspan 4 \
		-sticky we

	grid $w_files $w_errs $w_warns $w_vpane.f.sby -sticky nsew

	grid configure $w_vpane.f.sbx \
		-column 0 \
		-columnspan 4 \
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

		bind $i <Button-1>        "[cb _select_from_file_list %x %y]; break"
	}

	## error/warning description from one file

	ttk::label $w_vpane.o.t \
		-style Color.TLabel \
		-textvariable @current_path_label \
		-background gold \
		-foreground black \
		-justify right \
		-anchor e

	set ctxm $w_vpane.o.t.ctxm
	menu $ctxm -tearoff 0
	$ctxm add command \
		-label [mc Copy] \
		-command [cb _copy_path]
	bind_button3 $w_vpane.o.t "tk_popup $ctxm %X %Y"

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
	$w_lnos tag conf normal  -justify right -rmargin 5
	$w_lnos tag conf warning -justify right -rmargin 5 -foreground orange
	$w_lnos tag conf error   -justify right -rmargin 5 -foreground red

	text $w_hits \
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
	$w_hits tag conf normal
	$w_hits tag conf warning -foreground orange
	$w_hits tag conf error   -foreground red
	$w_hits tag conf jumpmark -elide 1
	$w_hits tag conf auxmark -elide 1

	delegate_sel_to $w_hits [list $w_lnos]

	set ui_hits_cols [list $w_lnos $w_hits]

	ttk::scrollbar $w_vpane.o.sbx \
		-orient h \
		-command [list $w_hits xview]

	ttk::scrollbar $w_vpane.o.sby \
		-orient v \
		-command [list scrollbar2many $ui_hits_cols yview]

	grid configure $w_vpane.o.t \
		-column 0 \
		-columnspan 3 \
		-sticky we

	grid $w_lnos $w_hits $w_vpane.o.sby -sticky nsew

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
	foreach i $ui_hits_cols {
		$i tag raise sel

		$i conf -yscrollcommand \
			"[list many2scrollbar $ui_hits_cols yview $w_vpane.o.sby]"

		set bind_cmd bind
		if {$i ne $w_hits} {
			set bind_cmd delegator_bind
		}
		$bind_cmd $i <Button-1>   "[cb _jump_to_hit_in_output %x %y]"
		bind $i <ButtonRelease-2> "[cb _open_from_hits %x %y]; break"
	}

	## command output and entry

	ttk::label $w_indicator \
		-style Color.TLabel \
		-textvariable @current_cmd_label \
		-background "cornflower blue" \
		-foreground white

	menu $m_configs -tearoff 0
	bind_button3 $w_indicator "[cb _popup_configs %X %Y]"

	text $w_output \
		-takefocus 0 \
		-highlightthickness 0 \
		-padx 0 \
		-pady 0 \
		-background white \
		-foreground black \
		-borderwidth 0 \
		-width 80 \
		-height 20 \
		-wrap none \
		-xscrollcommand [list $w_hpane.f.sbx set] \
		-state disabled \
		-font font_diff
	$w_output tag conf out
	$w_output tag conf note    -foreground "cornflower blue"
	$w_output tag conf warning -foreground orange
	$w_output tag conf error   -foreground red
	#$w_output tag conf path    -underline 1
	#$w_output tag conf pos     -underline 1
	$w_output tag conf path    -font font_diffitalic
	$w_output tag conf pos     -font font_diffitalic
	$w_output tag conf found   -background yellow
	$w_output tag conf currenthit -font font_diffbold

	foreach {n c} {0 black 1 red 2 green4 3 yellow4 4 blue4 5 magenta4 6 cyan4 7 grey60} {
		$w_output tag configure clr4$n -background $c
		$w_output tag configure clri4$n -foreground $c
		$w_output tag configure clr3$n -foreground $c
		$w_output tag configure clri3$n -background $c
	}
	$w_output tag configure clr1 -font font_diffbold
	$w_output tag configure clr4 -underline 1
	$w_output tag raise found
	$w_output tag raise sel

	ttk::scrollbar $w_hpane.f.sbx \
		-orient h \
		-command [list $w_output xview]

	ttk::scrollbar $w_hpane.f.sby \
		-orient v \
		-command [list $w_output yview]

	entry $w_entry \
		-font TkDefaultFont \
		-disabledforeground white \
		-disabledbackground "cornflower blue" \
		-selectbackground darkgray \
		-takefocus [cb _always_takefocus]

	grid configure $w_indicator \
		-column 0 \
		-columnspan 2 \
		-sticky we
	grid $w_output $w_hpane.f.sby -sticky nsew
	grid configure $w_hpane.f.sbx \
		-column 0 \
		-columnspan 2 \
		-sticky we

	set ui_finder [::searchbar::new \
		$w_hpane.f.f $w_output $w_entry \
		-column 0 \
		-columnspan 2 \
		]

	$w_output conf \
		-yscrollcommand \
		"[list $ui_finder scrolled]
		 [list $w_hpane.f.sby set]"

	grid configure $w_entry \
		-column 0 \
		-columnspan 2 \
		-sticky we

	grid columnconfigure $w_hpane.f \
		0 \
		-weight 1
	grid rowconfigure $w_hpane.f \
		1 \
		-weight 1

	bind $w_output <ButtonRelease-2> [cb _open_from_output %x %y]

	foreach i [list $w_output $w_entry [$ui_finder editor]] {
		bind $i <F7>           [list $ui_finder show]
		bind $i <$::M1B-Key-f> [list $ui_finder show]
		bind $i <Escape>       [list $ui_finder hide]
		bind $i <F3>           [list $ui_finder find_next]
		bind $i <Shift-F3>     [list $ui_finder find_prev]

		bind $i <Alt-Up>    "$w_output yview scroll -1 units; break"
		bind $i <Alt-Down>  "$w_output yview scroll  1 units; break"
		bind $i <Alt-Prior> "$w_output yview scroll -1 pages; break"
		bind $i <Alt-Next>  "$w_output yview scroll  1 pages; break"

		# scoll of file list
		bind $i <Alt-Shift-Up>    "[cb _files_scroll_line -1]; break"
		bind $i <Alt-Shift-Down>  "[cb _files_scroll_line  1]; break"
		bind $i <Alt-Shift-Prior> "[cb _files_scroll_page -1]; break"
		bind $i <Alt-Shift-Next>  "[cb _files_scroll_page  1]; break"
	}

	bind $w_entry <Return>          [cb _run]
	bind $w_entry <KP_Enter>        [cb _run]
	bind $w_entry <Key-Up>          [cb _prev_cmd]
	bind $w_entry <Key-Down>        [cb _next_cmd]
	bind $w_entry <$::M1B-Key-Up>   [cb _prev_build]
	bind $w_entry <$::M1B-Key-Down> [cb _next_build]
	bind $w_entry <Key-Prior>       [cb _search_prev_cmd]
	bind $w_entry <Key-Next>        [cb _search_next_cmd]
	bind $w_entry <$::M1B-Key-c>    [cb _cancel]
	bind $w_entry <Visibility>      [cb _visible]

	array set current_path_lno_hits {}
	trace add variable current_path write [cb _update_path_label]
	set current_path {}

	set state running
	trace add variable state write [cb _update_cmd_label]
	trace add variable current_cmd write [cb _update_cmd_label]
	set current_cmd {}

	set file_list [list]
	set current_file_list [list]
	array set file_info {}
	_reset_diag_list $this
	bind $w_diags <<ComboboxSelected>> [cb _select_diagnostics]
	array set build_tree {}
	array set static_build_tree {}

	# resolve vpath
	set vpath [file normalize [file join $::GIT_WORK_TREE $vpath]]

	# make the vpath relative to gitwork_dir, when this is an ancestor
	set cmd_dir $vpath
	if {[string first "$::GIT_WORK_TREE/" $cmd_dir] == 0} {
		set cmd_dir [string range $cmd_dir [string length "$::GIT_WORK_TREE/"] end]
	}
	if {$cmd_dir eq $::GIT_WORK_TREE} {
		set cmd_dir .
	}
	set static_build_tree(cwd) [list \
		120000 \
		blob \
		[git hash-object -w -t blob --stdin <<$cmd_dir]]

	# load history
	set cmd_history [list ""]
	set build_history [list]
	catch {
		set logfd [git_read log -g {--pretty=set hist_entry [list %H %T %at %ct {%s}]} $build_ref]
		while {[gets $logfd entry] >= 0} {
			eval $entry
			foreach {build_c build_t build_start_s build_end_s cmd} $hist_entry break
			set hist_entry [list $build_c $build_t [expr $build_end_s - $build_start_s] $cmd]
			lappend build_history $hist_entry
			set cmd [lindex $hist_entry 3]
			if {[lindex $cmd_history end] eq $cmd} {
				continue
			}
			lappend cmd_history $cmd
			unset hist_entry
		}
		close $logfd
	} err_info
}

method _run {} {
	global env

	if {$busy} return
	set busy 1

	if {[string trim [$w_entry get]] eq {}} {
		set busy 0
		return
	}
	set current_cmd [$w_entry get]

	set build_history_pos -1

	set run_nl {}

	set state running

	set file_list [list]
	set current_file_list [list]
	array unset file_info
	set diag_list [list "All" "Errors" "Warnings"]
	set current_diag 0
	set current_path {}
	array set build_tree {}

	foreach i $ui_files_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_errs conf -width [expr $ui_errs_width + 1]
	set ui_errs_width_max $ui_errs_width
	$w_warns conf -width [expr $ui_warns_width + 1]
	set ui_warns_width_max $ui_warns_width

	foreach i $ui_hits_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_lnos conf -width [expr $ui_lnos_width + 1]
	set ui_lnos_width_max $ui_lnos_width

	$w_output conf -state normal
	$w_output delete 0.0 end
	$w_output conf -state disabled
	$w_output tag remove found 1.0 end

	$w_errs conf -width [expr $ui_errs_width + 1]
	set ui_errs_width_max $ui_warns_width
	$w_warns conf -width [expr $ui_warns_width + 1]
	set ui_warns_width_max $ui_warns_width

	# record state of work tree
	if {[catch {
		exec git read-tree --index-output=$build_index --reset HEAD
		set ::GIT_INDEX_FILE $build_index
		exec git ls-files --exclude-standard -d -m -o -z | \
			git update-index -z --add --remove --stdin
		set build_tree(worktree) [list \
			040000 \
			tree \
			[git write-tree]]
		file delete $build_index
		git_reset_env
	} err]} {
		set state failed
		set busy 0
		file delete $build_index
		git_reset_env

		tk_messageBox \
			-icon error \
			-type ok \
			-title {git-gui: build: can't record state of worktree} \
			-message $err

		return
	}

	set dir_stack [list $vpath]
	set env_args [envargs [_get_envmods $this]]

	# environ
	if {[catch {
		# open pipe to git-hash-object
		set e_pipe [open "|cat" r+]
		fconfigure $e_pipe \
			-translation binary
		set e_out [git_write hash-object -t blob -w --stdin >@$e_pipe]
		fconfigure $e_out \
			-translation binary
		set cmd [concat env $env_args [list $shell -c "cd $vpath && env -0" >@$e_out]]
		eval exec $cmd
		close $e_out
		set build_tree(environ) [list \
			100644 \
			blob \
			[gets $e_pipe]]
		close $e_pipe
	} err]} {
		catch {close $e_out}
		catch {close $e_pipe}
		set state failed
		set busy 0

		tk_messageBox \
			-icon error \
			-type ok \
			-title {git-gui: build: can't record environment} \
			-message $err

		return
	}

	# open pipe to git-hash-object
	set output_hash_pipe [open "|cat" r+]
	fconfigure $output_hash_pipe \
		-translation binary
	set output_hash_out [git_write hash-object -t blob -w --stdin >@$output_hash_pipe]
	fconfigure $output_hash_out \
		-translation binary

	set build_start [exec date -R]
	set build_start_s [exec date +%s -d $build_start]
	set build_run_s 0
	set build_timer [after 250 [cb _update_runtime]]
	set cmd [concat [list | env] $env_args [list $shell -c "cd $vpath && $current_cmd" 2>@1]]
	if {[catch {set current_fd [open $cmd r]} err]} {
		set state failed
		set busy 0
		close $output_hash_pipe
		close $output_hash_out

		tk_messageBox \
			-icon error \
			-type ok \
			-title {git-gui: build: fatal error} \
			-message $err

		return
	}

	fconfigure $current_fd \
		-blocking 0 \
		-translation lf
	fileevent $current_fd readable [cb _read]
}

method _load {} {

	if {$build_history_pos < 0} {
		return
	}

	if {$busy} return
	set busy 1

	set run_nl {}

	set current_cmd {}
	set state loading

	foreach {build_c build_t build_run_s current_cmd} [lindex $build_history $build_history_pos] break
	$w_entry insert 0 $current_cmd

	set file_list [list]
	set current_file_list [list]
	array unset file_info
	_reset_diag_list $this
	set current_path {}

	foreach i $ui_files_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_errs conf -width [expr $ui_errs_width + 1]
	set ui_errs_width_max $ui_errs_width
	$w_warns conf -width [expr $ui_warns_width + 1]
	set ui_warns_width_max $ui_warns_width

	foreach i $ui_hits_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_lnos conf -width [expr $ui_lnos_width + 1]
	set ui_lnos_width_max $ui_lnos_width

	$w_output conf -state normal
	$w_output delete 0.0 end
	$w_output conf -state disabled
	$w_output tag remove found 1.0 end
	$w_output tag remove currenthit 1.0 end

	$w_errs conf -width [expr $ui_errs_width + 1]
	set ui_errs_width_max $ui_warns_width
	$w_warns conf -width [expr $ui_warns_width + 1]
	set ui_warns_width_max $ui_warns_width

	# load infos from build tree
	set build_load_info [list]
	set err [catch {
		set fd [git_read ls-tree $build_t -- cwd exit_status output]
		while {[gets $fd entry] >= 0} {
			foreach {infos path} [split $entry "\t"] break
			foreach {mode type sha1} [split $infos " "] break
			if {$type ne {blob}} {
				continue
			}
			switch -exact $path {
			cwd {
				if {$mode eq 120000} {
					lappend build_load_info [git cat-file blob $sha1]
				}
			}
			exit_status {
				if {$mode eq 100644} {
					lappend build_load_info [git cat-file blob $sha1]
				}
			}
			output {
				if {$mode eq 100644} {
					lappend build_load_info $sha1
				}
			}
			}
		}
		close $fd
	} exc]
	if {$err || [llength $build_load_info] != 3} {
		return
	}

	set dir_stack [list [file normalize [file join $::GIT_WORK_TREE [lindex $build_load_info 0]]]]

	# read output
	set current_fd [git_read cat-file blob [lindex $build_load_info 2]]
	fconfigure $current_fd \
		-blocking 0 \
		-translation lf
	fileevent $current_fd readable [cb _read [lindex $build_load_info 1]]
}

method _read {{exit_status {}}} {
	$w_output conf -state normal

	while {[gets $current_fd line] >= 0} {
		set scroll_pos [lindex [$w_output yview] 1]
		if {$run_nl eq {}} {
			set mark 1.0
		} else {
			set mark [$w_output index end]
		}

		# pass the original line to git-hash-object
		if {$exit_status eq {}} {
			puts $output_hash_out $line
		}

		# parse color sequences and remove them
		foreach {line markup} [parse_color_line $line] break
		set line [string map {\033 ^} $line]
		regsub {\r$} $line {} line

		set type out

		set ipath {}
		set ipos {}
		set imsg {}
		set itype {}
		if {   [regexp -indices {^(.*?): In [^ ]+ .+:} $line imatch ipath]
		    || [regexp -indices {^(?:In file included|                ) from (.*?)(?::([0-9]+(?::[0-9]+)?))?[:,]} $line imatch ipath ipos]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: the top level} $line imatch ipath ipos]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: At top level:} $line imatch ipath ipos]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: At global scope:} $line imatch ipath ipos]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?:   (?:instantiated|required) from .*$} $line imatch ipath ipos]
		    || [regexp -indices {^"(.*?)", line ([0-9]+): ((?:fatal )?(note|warning|WARNING|error): .*)$} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: ((?:fatal )?(note|warning|WARNING|error): .*)$} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?:\(([0-9]+)\))?: ((?:fatal )?(note|warning|WARNING|error): .*)$} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: .*? is expanded from...} $line imatch ipath ipos]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: installing [`'].*'} $line imatch ipath ipos]
		    || [regexp -indices {^(.*?):(?:\(.*?\)): ((undefined reference to) [`'].*')} $line imatch ipath imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: ((undefined reference to) [`'].*')} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: ((required file) [`'].*' not found)} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: ([^\s]*? (multiply defined in condition) .* \.\.\.)} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: (\.\.\. [`'].*' (previously defined here))} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?: (.* (does not appear in AM_CONDITIONAL))} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(.*?)(?::([0-9]+(?::[0-9]+)?))?:   ([`'].*' (included from here))} $line imatch ipath ipos imsg itype]
		    || [regexp -indices {^(PGC-([SW]-[0-9][0-9][0-9][0-9])-.*?) \((.*?): ([0-9]+)\)} $line imatch imsg itype ipath ipos]
		} {
			#puts "work dir:        $::GIT_WORK_TREE"
			#puts "current stack:   [lindex $dir_stack end]"
			#puts "output:          $line"

			set path [string range $line [lindex $ipath 0] [lindex $ipath 1]]
			set orig_path_len [string length $path]
			#puts "path:            $path"
			set path [file join [lindex $dir_stack end] $path]
			#puts "full path:       $path"
			set path [file normalize $path]
			#puts "normalized path: $path"

			# only remove the gitwork dir prefix, if the normalized path is
			# actually under the git work tree
			#puts "work dir prefix: [string range $path 0 [string length $::GIT_WORK_TREE]-1]"
			if {[string first $::GIT_WORK_TREE $path] == 0} {
				set path [string range $path [string length $::GIT_WORK_TREE]+1 end]
			}
			#puts "final path:      $path"

			if {$itype eq {}} {
				set type note
			} else {
				set type [string tolower [string range $line [lindex $itype 0] [lindex $itype 1]]]
				#puts "type:            $type"
				switch -glob -- $type {
				"undefined reference to" -
				"required file" -
				"does not appear in am_conditional" {
					set type "error"
				}
				"multiply defined in condition" {
					set type "warning"
				}
				"previously defined here" -
				"included from here" {
					set type "note"
				}
				s-[0-9][0-9][0-9][0-9] {
					set type "error"
				}
				w-[0-9][0-9][0-9][0-9] {
					set type "warning"
				}
				}
			}
			#puts ""

			# replace the original path in the output, when the file
			# exists
			if {[file exists [file join $::GIT_WORK_TREE $path]]} {

				if {$type eq "warning" || $type eq "error"} {

					# the message
					set msg [string range $line [lindex $imsg 0] [lindex $imsg 1]]

					# the linepos
					set pos {}
					if {$ipos ne {}} {
						set pos [string range $line [lindex $ipos 0] [lindex $ipos 1]]
					}

					set cat {}
					if {[regexp { \[([^[]+)\]$} $msg _ cat]} {
						_update_diag_list $this $cat
					}

					# (line in the output, line in the file, type of hit, message)
					set new_hit [list $mark $pos $type $msg $cat]

					set exists [array get file_info $path]
					if {$exists eq {}} {
						# path unknown, add it
						array set file_info [list $path [list 0 0 [list]]]
						# append this file to the list of path
						lappend file_list $path
					}
					foreach {p info} [array get file_info $path] break
					foreach {nwarnings nerrors hits} $info break

					set hit_exists 0
					foreach e_hit $hits {
						foreach {e_mark e_pos e_type e_msg e_cat} $e_hit break

						if {$pos eq $e_pos
								&& $type eq $e_type
								&& $msg eq $e_msg} {
							set hit_exists 1
							break
						}
					}
					if {!$hit_exists} {
						if {$type eq "error"}   {incr nerrors}
						if {$type eq "warning"} {incr nwarnings}

						lappend hits $new_hit
						set info [list $nwarnings $nerrors $hits]

						array set file_info [list $path $info]
						set file_list_needs_update 1
					}
				}

				set line [string replace $line [lindex $ipath 0] [lindex $ipath 1] $path]

				# convert ipath and ipos after the original path was replaced
				set offset [expr [string length $path] - $orig_path_len]

				set ipath [lreplace $ipath 1 1 [expr [lindex $ipath 1] + $offset]]

				# shift the ipos only when it is not infront of the path
				if {$ipos ne {} && [lindex $ipos 0] > [lindex $ipath 0]} {
					set ipos [list \
							[expr [lindex $ipos 0] + $offset] \
							[expr [lindex $ipos 1] + $offset]]
				}
			} else {
				# file does not exists, clear ipath and ipos, so that there will
				# be no tags for them
				set ipath {}
				set ipos {}
			}
			set markup [list]
		}

		if {[regexp {^.*?: Entering directory [`'](.*)'} $line match path]} {
			# huh, path maybe empty?
			if {$path ne {}} {
				lappend dir_stack [file normalize [file join [lindex $dir_stack end] $path]]
			}
			set type note
			set markup [list]
		}
		if {[regexp {^.*?: Leaving directory [`'](.*)'} $line match path]} {
			# huh, path maybe empty?
			if {$path ne {}} {
				set dir_stack [lrange $dir_stack 0 end-1]
			}
			set type note
			set markup [list]
		}

		$w_output insert end "$run_nl"
		set run_nl "\n"

		if {$markup ne {}} {
			$w_output insert end "$line"
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
					set a "$mark linestart + $posbegin chars"
					set b "$mark linestart + $posend chars"
					catch {$w_output tag add $prefix$style $a $b}
				}
			}
		} else  {
			$w_output insert end "$line" $type
			if {$ipath ne {}} {
				# tag the path
				set i1 [$w_output index "$mark + [lindex $ipath 0] chars"]
				set i2 [$w_output index "$mark + [lindex $ipath 1] chars + 1 c"]
				$w_output tag add path $i1 $i2

				# only add the pos tag, when there is a path too
				if {$ipos ne {}} {
					# tag the pos
					set i1 [$w_output index "$mark + [lindex $ipos 0] chars"]
					set i2 [$w_output index "$mark + [lindex $ipos 1] chars + 1 c"]
					$w_output tag add pos $i1 $i2
				}
			}
		}

		if {1.0 == $scroll_pos} {
			$w_output yview moveto 1.0
		}
	}

	fconfigure $current_fd -blocking 1
	if {[eof $current_fd]} {
		if {$exit_status eq {}} {
			after cancel $build_timer
			set build_end [exec date -R]
			set build_run_s [expr [exec date +%s -d $build_end] - $build_start_s]

			set state committing
			set exit_status 0
			if {[catch {close $current_fd} err errDict]} {
				set exit_status 1
				if {[dict get $errDict -code] eq 1} {
					set exit_status [lindex [dict get $errDict -errorcode] 2]
				}
			}

			# close the fd to git-hash-object, so that we can read the
			# result on the other end in
			close $output_hash_out
			set build_tree(output) [list \
				100644 \
				blob \
				[gets $output_hash_pipe]]
			close $output_hash_pipe
			set build_tree(exit_status) [list \
				100644 \
				blob \
				[git hash-object -w -t blob --stdin <<$exit_status]]

			_commit_build $this

		} else {
			catch {close $current_fd}
		}

		_safe_cmd $this

		set file_list_needs_update 1

		if {$exit_status} {
			set state failed
		} else {
			set state succeeded
		}
		set busy 0
	} else {
		fconfigure $current_fd -blocking 0
	}

	$w_output conf -state disabled

	if {$file_list_needs_update} {
		_update_file_list $this
	}

} ifdeleted {
	catch {close $current_fd}
	catch {close $output_hash_out}
	catch {gets $output_hash_pipe}
	catch {close $output_hash_pipe}
}

method _update_file_list {} {
	# TODO: remeber current position and selection
	# we append only, or update the number of errors/warnings
	set files_scroll_pos [$w_files yview]
	set hits_scroll_pos [$w_hits yview]

	if {$file_list_busy} {
		return
	}
	set file_list_busy 1
	set file_list_needs_update 0
	set current_file_list [list]

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
		$i conf -state normal
		$i delete 0.0 end
	}
	$w_errs conf -width [expr $ui_errs_width + 1]
	set ui_errs_width_max $ui_errs_width
	$w_warns conf -width [expr $ui_warns_width + 1]
	set ui_warns_width_max $ui_warns_width

	set fl_nl {}

	foreach path $file_list {
		foreach {p info} [array get file_info $path] break
		foreach {nwarnings nerrors hits} $info break

		# filter based on diagnostic type
		if {$current_diag == 1} {
			if {$nerrors == 0} continue
			set nwarnings 0
		} elseif {$current_diag == 2} {
			if {$nwarnings == 0} continue
			set nerrors 0
		} elseif {$current_diag > 2} {
			set nerrors 0
			set nwarnings 0
			set diag [lindex $diag_list $current_diag]
			foreach hit $hits {
				foreach {mark pos type msg cat} $hit break
				if {$cat ne $diag} continue
				if {$type eq "error"} {incr nerrors}
				if {$type eq "warning"} {incr nwarnings}
			}
			if {($nerrors + $nwarnings) == 0} continue
		}

		foreach i $ui_files_cols {$i insert end "$fl_nl"}
		set fl_nl "\n"

		lappend current_file_list $path

		$w_files insert end "[escape_path $path]" default

		if {$nerrors == 0} {
			set nerrors {}
		}
		$w_errs  insert end "$nerrors" count
		set len [string length $nerrors]
		if {$ui_errs_width_max < $len} {
			set ui_errs_width_max $len
		}

		if {$nwarnings == 0} {
			set nwarnings {}
		}
		$w_warns insert end "$nwarnings" count
		set len [string length $nwarnings]
		if {$ui_warns_width_max < $len} {
			set ui_warns_width_max $len
		}
	}

	if {$ui_errs_width != $ui_errs_width_max} {
		$w_errs  conf -width [expr $ui_errs_width_max + 1]
	}
	if {$ui_warns_width != $ui_warns_width_max} {
		$w_warns conf -width [expr $ui_warns_width_max + 1]
	}
	foreach i $ui_files_cols {
		$i conf -state disabled
	}

	# restore position
	many2scrollbar $ui_files_cols yview $w_vpane.f.sby \
			[lindex $files_scroll_pos 0] \
			[lindex $files_scroll_pos 1]

	set file_list_busy 0

	if {[llength $current_file_list] != 0} {
		if {$current_path eq {}} {
			# select the first file, when no one is selected
			set current_path [lindex $current_file_list 0]
			set lno 1
		} else {
			# restore selection of current path
			set lno [lsearch -exact $current_file_list $current_path]
			incr lno
		}

		foreach i $ui_files_cols {
			$i tag add in_sel $lno.0 "$lno.0 + 1 line"
		}
	}

	# reaload file and jump to last scroll pos
	_show_hits_for_file $this $current_path $hits_scroll_pos
}

method _select_from_file_list {x y} {
	if {$file_list_busy} return

	# TODO: remeber scroll pos, when updating the same path?

	set lno [lindex [split [$w_files index @0,$y] .] 0]
	set path [lindex $current_file_list [expr {$lno - 1}]]

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
	}

	if {$path eq {}} {
		return
	}

	foreach i $ui_files_cols {
		$i tag add in_sel $lno.0 "$lno.0 + 1 line"
	}

	_show_hits_for_file $this $path
}

method _show_hits_for_file {path {scroll_pos {}}} {
	if {$hits_busy} return
	set hits_busy 1

	set current_path $path

	foreach i $ui_hits_cols {
		$i conf -state normal
		$i delete 0.0 end
		$i conf -state disabled
	}
	$w_lnos conf -width [expr $ui_lnos_width + 1]
	set ui_lnos_width_max $ui_lnos_width

	set hits_nl {}

	# re-build current_path_lno_hits
	array set current_path_lno_hits {}

	if {$current_path eq {}} {
		set hits_busy 0
		return
	}

	foreach {p path_info} [array get file_info $current_path] break
	foreach {nwarnings nerrors path_hits} $path_info break

	set diag [lindex $diag_list $current_diag]
	foreach hit $path_hits {
		foreach {mark pos type msg cat} $hit break

		# filter based on diagnostic type
		if {   ($current_diag == 1 && $type != "error")
		    || ($current_diag == 2 && $type != "warning")
		    || ($current_diag >  2 && $cat ne $diag)} continue

		set lno 0
		if {$pos ne {}} {
			set lno [lindex [split $pos :] 0]
		}

		set lno_entry [array get current_path_lno_hits $lno]
		if {$lno_entry eq {}} {
			# lno unknown, add it
			set lno_info [list -1 [list]]
		} else {
			foreach {_lno lno_info} $lno_entry break
		}
		foreach {primary_hit lno_hits} $lno_info break
		if {$primary_hit != -1} {
			foreach {p_mark p_pos p_type p_msg} [lindex $lno_hits $primary_hit] break
			if {$type eq "error" && $p_type eq "warning"} {
				set primary_hit [llength $lno_hits]
			}
		} else {
			set primary_hit 0
		}
		lappend lno_hits $hit
		array set current_path_lno_hits [list $lno [list $primary_hit $lno_hits]]
	}

	set lnos [lsort -integer [array names current_path_lno_hits]]

	# insert hits without line information
	if {[llength $lnos] > 0 && [lindex $lnos 0] == 0} {
		set lnos [lrange $lnos 1 end]

		foreach i $ui_hits_cols {$i conf -state normal}

		foreach {lno info} [array get current_path_lno_hits 0] break
		foreach {primary_hit hits} $info break
		foreach hit $hits {
			foreach {mark pos type msg cat} $hit break

			$w_lnos insert end "$hits_nl"
			$w_hits insert end "$hits_nl"
			set hits_nl "\n"

			$w_hits insert end "$mark" jumpmark
			$w_hits insert end "$msg" $type
		}

		foreach i $ui_hits_cols {$i conf -state disabled}
	}

	if {[llength $lnos] == 0} {
		if {$scroll_pos ne {}} {
			many2scrollbar $ui_hits_cols yview $w_vpane.o.sby \
					[lindex $scroll_pos 0] \
					[lindex $scroll_pos 1]
		}
		set hits_busy 0
		return
	}

	set cmd [list | git grep --no-color -h -n -p -3]
	set args [list]
	foreach lno $lnos {
		lappend args -@ $lno
	}
	if {[file pathtype $current_path] eq "relative"} {
		if {$build_history_pos >= 0} {
			foreach {build_c build_t build_run_s _cmd} [lindex $build_history $build_history_pos] break
			lappend args "$build_c:worktree"
		}
	} else {
		set ::GIT_WORK_TREE "/"
		lappend cmd --no-index
	}
	lappend args -- $current_path
	lappend cmd {*}$args

	if {[catch {set fd [open $cmd r]} err]} {
		git_reset_env
		# fallback to GNU nl and GNU grep to get the content
		set cmd2 [list | nl -s: -w1 -ba -- $current_path | env -u GREP_OPTIONS grep --color=never -C 3]
		foreach lno $lnos {
			lappend cmd2 -e "^$lno:"
		}
		if {[catch {set fd [open $cmd2 r]} err2]} {
			tk_messageBox \
				-icon error \
				-type ok \
				-title {gui-grep: fatal error} \
				-message "failed: $cmd\n$err\n\nfallback failed: $cmd2\n$err2"
			set hits_busy 0
			return
		}
		set cmd $cmd2
	}
	git_reset_env

	fconfigure $fd -eofchar {}
	fconfigure $fd \
		-blocking 0 \
		-buffering full \
		-buffersize 512 \
		-translation lf
	fileevent $fd readable [cb _read_file $fd $scroll_pos]
}

method _read_file {fd scroll_pos} {
	foreach i $ui_hits_cols {$i conf -state normal}

	while {[gets $fd line] >= 0} {

		set mark {}
		set auxmsg {}

		# catch hunk sep --
		if {[regexp {^--} $line]} {
			set lno "--"
			set line {}
		} else {
			# remove any color from lno and sep
			regexp {^(\d+)([-:=])(.*)$} $line match lno line_type line
			regsub {\r$} $line {} line
			if {   $line_type eq {:}
			    && [array get current_path_lno_hits $lno] ne {}} {
				foreach {lno info} [array get current_path_lno_hits $lno] break
				foreach {primary_hit hits} $info break

				# the actual line has the mark and the aux message of the primamry hit
				foreach {mark h_lno h_type auxmsg} [lindex $hits $primary_hit] break

				foreach hit $hits {
					foreach {h_mark h_pos h_type h_msg h_cat} $hit break

					$w_lnos insert end "$hits_nl"
					$w_hits insert end "$hits_nl"
					set hits_nl "\n"

					$w_lnos insert end "$h_pos" $h_type
					set len [string length $h_pos]
					if {$ui_lnos_width_max < $len} {
						set ui_lnos_width_max $len
					}

					$w_hits insert end "$h_mark" jumpmark
					$w_hits insert end "$h_msg" $h_type
				}
			}
		}

		$w_lnos insert end "$hits_nl"
		$w_hits insert end "$hits_nl"
		set hits_nl "\n"

		$w_lnos insert end "$lno" normal
		set len [string length $lno]
		if {$ui_lnos_width_max < $len} {
			set ui_lnos_width_max $len
		}

		if {$mark ne {}} {
			$w_hits insert end "$mark" jumpmark
		}
		if {$auxmsg ne {}} {
			$w_hits insert end "$auxmsg" auxmark
		}
		$w_hits insert end "$line" normal
	}

	if {[eof $fd]} {
		close $fd

		#update line number column width
		if {$ui_lnos_width != $ui_lnos_width_max} {
			$w_lnos conf -width [expr $ui_lnos_width_max + 1]
		}

		if {$scroll_pos ne {}} {
			many2scrollbar $ui_hits_cols yview $w_vpane.o.sby \
					[lindex $scroll_pos 0] \
					[lindex $scroll_pos 1]
		}

		set hits_busy 0
	}

	foreach i $ui_hits_cols {$i conf -state disabled}

} ifdeleted {
	catch {close $fd}
}

method _jump_to_hit_in_output {x y} {
	if {$hits_busy} {
		return
	}

	if {$current_path eq {}} {
		return
	}

	set imark [$w_hits tag nextrange jumpmark "@$x,$y linestart" "@$x,$y lineend"]
	if {$imark eq {}} {
		return
	}

	set mark [$w_hits get [lindex $imark 0] [lindex $imark 1]]
	$w_output see $mark
	$w_output tag remove currenthit 0.0 end
	$w_output tag add currenthit "$mark linestart" "$mark lineend"
}

method _open_from_hits {x y} {
	if {$hits_busy} {
		return
	}

	if {$current_path eq {}} {
		return
	}

	set lno 0
	set aux {}
	set wlno [$w_lnos search -regexp {^[[:digit:]]+(?::[[:digit:]]+)?$} "@0,$y linestart" end]
	if {$wlno eq {}} {
		set wlno [$w_lnos search -backwards -regexp {^[[:digit:]]+(?::[[:digit:]]+)?$} "@0,$y linestart" 1.0]
	}
	if {$wlno ne {}} {
		set lno [lindex [split [$w_lnos get "$wlno" "$wlno lineend"] :] 0]
		set iaux [$w_hits tag nextrange auxmark "@$x,$y linestart" "@$x,$y lineend"]
		if {$iaux ne {}} {
			set aux [$w_hits get [lindex $iaux 0] [lindex $iaux 1]]
		} else {
			set aux [$w_hits get -displaychars "@0,$y linestart" "@0,$y lineend"]
		}
	}

	open_in_git_editor $current_path $lno 0 $aux
}

method _safe_cmd {} {
	set cmd [$w_entry get]
	$w_entry delete 0 end
	if {[lindex $cmd_history 1] ne $cmd} {
		set cmd_history [linsert $cmd_history 1 $cmd]
		set cmd_history [lreplace $cmd_history 0 0 ""]
	}
	set cmd_history_pos 0
}

method _prev_cmd {} {
	if {[expr [llength $cmd_history] - 1] > $cmd_history_pos} {
		if {$cmd_history_pos == 0} {
			set cmd_history [lreplace $cmd_history 0 0 [$w_entry get]]
		}
		incr cmd_history_pos
		$w_entry delete 0 end
		$w_entry insert 0 [lindex $cmd_history $cmd_history_pos]
	}
}

method _next_cmd {} {
	if {0 < $cmd_history_pos} {
		incr cmd_history_pos -1
		$w_entry delete 0 end
		$w_entry insert 0 [lindex $cmd_history $cmd_history_pos]
	}
}

method _search_prev_cmd {} {
	set cursor [$w_entry index insert]
	if {$cursor == 0} {
		_prev_cmd $this
		$w_entry icursor $cursor
		return
	}
	incr cursor -1
	set prefix [string range [$w_entry get] 0 $cursor]
	for {set i [expr $cmd_history_pos + 1]} {$i < [llength $cmd_history]} {incr i} {
		set cmd [lindex $cmd_history $i]
		if {[string range $cmd 0 $cursor] eq $prefix} {
			set cmd_history_pos $i
			$w_entry delete 0 end
			$w_entry insert 0 $cmd
			$w_entry icursor [expr $cursor + 1]
			break
		}
	}
}

method _search_next_cmd {} {
	set cursor [$w_entry index insert]
	if {$cursor == 0} {
		_next_cmd $this
		$w_entry icursor $cursor
		return
	}
	incr cursor -1
	set prefix [string range [$w_entry get] 0 $cursor]
	for {set i [expr $cmd_history_pos - 1]} {$i > 0} {incr i -1} {
		set cmd [lindex $cmd_history $i]
		if {[string range $cmd 0 $cursor] eq $prefix} {
			set cmd_history_pos $i
			$w_entry delete 0 end
			$w_entry insert 0 $cmd
			$w_entry icursor [expr $cursor + 1]
			break
		}
	}
}

method _prev_build {} {
	if {[llength $build_history] > ($build_history_pos + 1)} {
		incr build_history_pos
		_load $this
	}
}

method _next_build {} {
	if {0 < $build_history_pos} {
		incr build_history_pos -1
		_load $this
	}
}

method _cancel {} {
	if {$build_history_pos >= 0} return
	if {$busy} {
		after cancel $build_timer
		set build_end_s [exec date +%s]
		set build_end [exec date -d @$build_end_s -R]
		set build_run_s [expr $build_end_s - $build_start_s]

		set state canceling
		fconfigure $current_fd -blocking 1
		foreach p [pid $current_fd] {
			catch {exec kill $p}
		}
		catch {close $output_hash_out}
		catch {gets $output_hash_pipe}
		catch {close $output_hash_pipe}
		set is_err 0
		if {[catch {close $current_fd} err opts]} {
			set details [dict get $opts -errorcode]
			# we killed the child ourself, don't handle this as an error
			if {   [lindex $details 0] ne {CHILDKILLED}
			    && [lindex $details 2] ne {SIGKILL}} {
				set is_err 1
			}
		}

		if {$is_err} {
			set state failed
		} else {
			set state succeeded
		}
		set busy 0
	}
}

method _select_diagnostics {} {
	$w_diags selection clear
	set current_diag [$w_diags current]
	set file_list_needs_update 1
	_update_file_list $this
}

method _reset_diag_list {} {
	set diag_list [list "All" "Errors" "Warnings"]
	set current_diag 0
	set width 0
	foreach diag $diag_list {
		set cx [string length $diag]
		if {$cx > $width} {set width $cx}
	}
	$w_diags configure -values $diag_list
	$w_diags configure -width $width
	$w_diags current $current_diag
}

method _update_diag_list {diag} {
	set exists [lsearch -exact $diag_list $diag]
	if {$exists != -1} return

	lappend diag_list $diag
	$w_diags configure -values $diag_list

	set cx [string length $diag]
	if {$cx > [$w_diags cget -width]} {
		$w_diags configure -width $cx
	}
	$w_diags current $current_diag
}

method _always_takefocus {w} {
	return 1
}

method reorder_bindtags {} {
	foreach i [list $w_entry] {
		bindtags $i [list all $i [winfo class $i] .]
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

method _open_from_output {x y} {
	set ipath [$w_output tag nextrange path "@$x,$y linestart" "@$x,$y lineend"]
	if {$ipath ne {}} {
		set path [$w_output get [lindex $ipath 0] [lindex $ipath 1]]

		set lno 0
		set ipos [$w_output tag nextrange pos "@$x,$y linestart" "@$x,$y lineend"]
		if {$ipos ne {}} {
			set pos [$w_output get [lindex $ipos 0] [lindex $ipos 1]]
			set lno [lindex [split $pos :] 0]
		}

		open_in_git_editor $path $lno
	}
}

method _update_path_label {args} {
	# any change to current_path makes the current_path_lno_hits array invalid
	array unset current_path_lno_hits

	if {$current_path eq {}} {
		set current_path_label ""
	} else {
		set current_path_label "File: [escape_path $current_path]"
	}
}

method _copy_path {} {
	clipboard clear
	clipboard append \
		-format STRING \
		-type STRING \
		-- $current_path
}

method _update_cmd_label {args} {
	$w_entry conf -state normal
	if {$current_cmd eq {}} {
		set current_cmd_label ""
	} else {
		switch $state {
		running {
			set current_cmd_label "[_get_runtime $this] Running command: $current_cmd"
			$w_entry conf -state disabled
			$w_indicator conf -foreground white -background "cornflower blue"
		}
		succeeded {
			set current_cmd_label "[_get_runtime $this] Successful command: $current_cmd"
			$w_indicator conf -foreground black -background lightgreen
		}
		failed {
			set current_cmd_label "[_get_runtime $this] Failed command: $current_cmd"
			$w_indicator conf -foreground black -background lightsalmon
		}
		canceling {
			set current_cmd_label "[_get_runtime $this] Canceling command: $current_cmd"
			$w_indicator conf -foreground black -background cyan
		}
		committing {
			set current_cmd_label "[_get_runtime $this] Committing command: $current_cmd"
			$w_indicator conf -foreground black -background orange
		}
		loading {
			set current_cmd_label "[_get_runtime $this] Loading command: $current_cmd"
			$w_entry conf -state disabled
			$w_indicator conf -foreground white -background "cornflower blue"
		}
		}

		if {$state_change_cb ne {}} {
			eval $state_change_cb $state
		}
	}
}

method _get_runtime {} {
	set m [expr $build_run_s / 60]
	set s [expr $build_run_s % 60]
	if {$s < 10} {
		set s "0$s"
	}
	if {$build_history_pos >= 0
		&& ![catch {set relative_start "[exec git log -1 -g --pretty=%ar $build_ref@{$build_history_pos}]"} err]} {
		return "@{$relative_start} \[$m:$s\]"
	}
	return "\[$m:$s\]"
}

method _update_runtime {} {
	set new_build_run_s [expr [exec date +%s] - $build_start_s]
	if {$new_build_run_s > $build_run_s} {
		set build_run_s $new_build_run_s
		set state $state
	}
	set build_timer [after 250 [cb _update_runtime]]
}

method _commit_build {} {
	set ls_tree {}
	foreach name [array names static_build_tree] {
		foreach {mode type hash} $static_build_tree($name) break
		append ls_tree "$mode $type $hash\t$name\n"
	}
	foreach name [array names build_tree] {
		foreach {mode type hash} $build_tree($name) break
		append ls_tree "$mode $type $hash\t$name\n"
	}
	set tree [git mktree <<$ls_tree]

	set cmd [$w_entry get]
	set cmdn "$cmd\n"

	set restore_envs [modify_env [list \
		GIT_AUTHOR_DATE    1 $build_start \
		GIT_COMMITTER_DATE 1 $build_end \
		]]

	set commit [git commit-tree $tree <<$cmdn]

	restore_env $restore_envs

	set reflog [gitdir logs $build_ref]
	if {[file exists $reflog] || ![catch {
		file mkdir [file dirname $reflog]
		set fd [open $reflog a]
		close $fd
	}]} {
		exec git update-ref -m $cmd $build_ref $commit
	}

	set build_history [linsert $build_history 0 [list \
		$commit \
		$tree \
		$build_run_s \
		$cmd]]
	set build_history_pos 0
}

method _files_scroll_line {dir} {
	if {$file_list_busy} return

	if {[catch {$w_files index in_sel.first}]} {
		return
	}

	set lno [lindex [split [$w_files index in_sel.first] .] 0]
	incr lno $dir

	set path [lindex $current_file_list [expr {$lno - 1}]]
	if {$path eq {}} {
		return
	}

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
		$i tag add in_sel $lno.0 "$lno.0 + 1 line"
	}
	$w_files see $lno.0

	_show_hits_for_file $this $path
}

method _files_scroll_page {dir} {
	if {$file_list_busy} return

	set page [expr {
		int(
		  ceil(
		    ([lindex [$w_files yview] 1] - [lindex [$w_files yview] 0])
		    * [llength $current_file_list]
		  )
		)}]
	set lno [expr "[lindex [split [$w_files index in_sel.first] .] 0] + $dir * $page"]
	if {1 > $lno} {set lno 1}
	if {$lno > [llength $current_file_list]} {set lno [llength $current_file_list]}

	set path [lindex $current_file_list [expr {$lno - 1}]]
	if {$path eq {}} {
		return
	}

	foreach i $ui_files_cols {
		$i tag remove in_sel 0.0 end
		$i tag add in_sel $lno.0 "$lno.0 + 1 line"
	}
	$w_files see $lno.0

	_show_hits_for_file $this $path
}

method _visible {} {
	if {[$ui_finder visible]} {
		focus [$ui_finder editor]
	} else {
		focus $w_entry
	}
}

method _get_envmods {} {
	set env_mods $envmods
	_load_config $this
	foreach config $configmods {
		while {1} {
			set alias [_get_buildconfig $this $config alias $config]
			if {$alias == $config} break
			set config $alias
		}
		foreach mod [_get_buildconfig $this $config] {
			if {[regexp {^([A-Za-z0-9_]+)\s*((?:[-+%].?)?=)\s*(.*)$} $mod match name op value]} {
				lappend env_mods $name $op $value
			} elseif {[regexp {^!([A-Za-z0-9_]+)$} $mod match name]} {
				lappend env_mods $name ! {}
			}
		}
	}
	return $env_mods
}

method _popup_configs {X Y} {
	if {$busy} return

	_load_config $this

	$m_configs delete 0 end

	array unset selected_configs

	array unset menu_hierarchy
	# build the menu hierarchy first without actually entries
	foreach full_config [lsort [array names buildconfig_config gui.buildconfig.*.env]] {
		set config [string range $full_config [string length {gui.buildconfig.}] end-[string length {.env}]]
		set first  [string toupper [string range $config 0 0]]
		set menupath "$first/$config"

		set names [split $menupath "/"]
		set parent $m_configs
		for {set i 0} {$i < [llength $names]-1} {incr i} {
			set subname [join [lrange $names 0 $i] "/"]

			if {![info exists menu_hierarchy($subname)]} {
				set subid $parent.t[incr buildconfig_menu_id]
				$parent add cascade \
						-label [lindex $names $i] \
						-menu $subid
				menu $subid -tearoff 0
				$parent index end
				set menu_hierarchy($subname) $subid
			}
			set parent $menu_hierarchy($subname)
		}
	}

	foreach full_config [lsort [array names buildconfig_config gui.buildconfig.*.env]] {
		set config [string range $full_config [string length {gui.buildconfig.}] end-[string length {.env}]]
		if {[lsearch -exact $configmods $config] >= 0} {
			set selected_configs($config) 1
		} else {
			set selected_configs($config) 0
		}

		set first  [string toupper [string range $config 0 0]]
		set menupath "$first/$config"

		set names [split $menupath "/"]
		set parent $m_configs
		for {set i 0} {$i < [llength $names]-1} {incr i} {
			set subname [join [lrange $names 0 $i] "/"]
			set parent $menu_hierarchy($subname)
		}

		if {[info exists menu_hierarchy($menupath)]} {
			$menu_hierarchy($menupath) insert 0 separator
			$menu_hierarchy($menupath) insert 0 checkbutton \
				-label [_get_buildconfig $this $config title "This"] \
				-command [cb _update_configs_from_menu] \
				-variable ${__this}::selected_configs($config) \
				-onvalue  1 \
				-offvalue 0
		} else {
			$parent add checkbutton \
				-label [_get_buildconfig $this $config title [lindex $names end]] \
				-command [cb _update_configs_from_menu] \
				-variable ${__this}::selected_configs($config) \
				-onvalue  1 \
				-offvalue 0
		}
	}
	if {[array size selected_configs] > 0} {
		tk_popup $m_configs $X $Y
	}
}

method _load_config {} {
	global repo_config
	load_config 0
	array unset buildconfig_config
	# make this a list and iterate over all commands
	set cmd [get_config gui.build.configcommand {}]
	if {$cmd ne {}} {
		_parse_config buildconfig_config [list open_read $cmd]
	}
	foreach name [array names repo_config] {
		if {[catch {set v $buildconfig_config($name)}]} {
			set buildconfig_config($name) $repo_config($name)
		}
	}
}

method _get_buildconfig {config {var {env}} {default {}}} {
	if {[catch {set v $buildconfig_config(gui.buildconfig.$config.$var)}]} {
		return $default
	} else {
		return $v
	}
}

method _update_configs_from_menu {} {
	set configmods [list]
	foreach config [array names selected_configs] {
		if {$selected_configs($config)} {
			lappend configmods $config
		}
	}
}

}

proc envargs {envmods} {
	global env
	array set newenv [array get env]

	foreach {name op value} $envmods {
		set old {}
		if {[info exists newenv($name)]} {
			# remember, that the variable was set
			set old $newenv($name)
		}
		set sep ""
		if {![regexp {([-+%])(.)=} $op match op sep]} {
			regexp {([-+%])=} $op match op
		}
		if {[string first $op "-+%"] >= 0 && $old ne {}} {
			if {$sep ne ""} {
				set l [split $old $sep]
				set e [lsearch -exact $l $value]
				while {$e >= 0} {
					set l [concat [lrange $l 0 $e-1] [lrange $l $e+1 end]]
					set e [lsearch -exact $l $value]
				}
				set old [join $l $sep]
			} else {
				set f [string first $value $old]
				while {$f >= 0} {
					set old [string replace $old $f $f+[string length $value]]
					set f [string first $value $old]
				}
			}
			if {$op eq "+"} {
				set newenv($name) ${old}${sep}${value}
			} elseif {$op eq "%"} {
				set newenv($name) ${value}${sep}${old}
			} else {
				# {$op eq "-"}
				set newenv($name) ${old}
			}
		} elseif {$op eq "!"} {
			catch {unset newenv($name)}
		} else {
			set newenv($name) $value
		}
	}

	set env_args [list]
	foreach name [array names env] {
		if {![info exists newenv($name)]} {
			lappend env_args -u $name
		}
	}
	foreach name [array names newenv] {
		if {![info exists env($name)]} {
			lappend env_args $name=$newenv($name)
		} elseif {$env($name) ne $newenv($name)} {
			lappend env_args $name=$newenv($name)
		}
	}
	unset newenv

	return $env_args
}

proc modify_env {envmods} {
	global env

	set restore_envs [list]
	foreach {name set value} $envmods {
		if {[info exists env($name)]} {
			# remember, that the variable was set
			lappend restore_envs $name 1 $env($name)
		} else {
			lappend restore_envs $name 0 {}
		}
		if {$set} {
			set env($name) $value
		} else {
			catch {unset env($name)}
		}
	}
	return $restore_envs
}

proc restore_env {envrestores} {
	global env
	foreach {name set value} $envrestores {
		if {$set} {
			set env($name) $value
		} else {
			unset env($name)
		}
	}
}
