class full_browser {

image create photo ::full_browser::img_find    -data {R0lGODlhEAAQAIYAAPwCBCQmJDw+PBQSFAQCBMza3NTm5MTW1HyChOT29Ozq7MTq7Kze5Kzm7Oz6/NTy9Iza5GzGzKzS1Nzy9Nz29Kzq9HTGzHTK1Lza3AwKDLzu9JTi7HTW5GTCzITO1Mzq7Hza5FTK1ESyvHzKzKzW3DQyNDyqtDw6PIzW5HzGzAT+/Dw+RKyurNTOzMTGxMS+tJSGdATCxHRydLSqpLymnLSijBweHERCRNze3Pz69PTy9Oze1OTSxOTGrMSqlLy+vPTu5OzSvMymjNTGvNS+tMy2pMyunMSefAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAEAAAAALAAAAAAQABAAAAe4gACCAAECA4OIiAIEBQYHBAKJgwIICQoLDA0IkZIECQ4PCxARCwSSAxITFA8VEBYXGBmJAQYLGhUbHB0eH7KIGRIMEBAgISIjJKaIJQQLFxERIialkieUGigpKRoIBCqJKyyLBwvJAioEyoICLS4v6QQwMQQyLuqLli8zNDU2BCf1lN3AkUPHDh49fAQAAEnGD1MCCALZEaSHkIUMBQS8wWMIkSJGhBzBmFEGgRsBUqpMiSgdAD+BAAAh/mhDcmVhdGVkIGJ5IEJNUFRvR0lGIFBybyB2ZXJzaW9uIDIuNQ0KqSBEZXZlbENvciAxOTk3LDE5OTguIEFsbCByaWdodHMgcmVzZXJ2ZWQuDQpodHRwOi8vd3d3LmRldmVsY29yLmNvbQA7}
image create photo ::full_browser::img_clear   -data {R0lGODlhEAAQAIABAAAAAP///yH5BAEKAAEALAAAAAAQABAAAAImjI+py70AowQINmpsxhYH/U3flkgZWUUnGpoeqHXpVU6ig+e6UQAAOw==}

field w
field w_files
field w_filter

field filter {}
field pattern {}
field filter_show_dot 0
field busy 0
field matches
field need_reload 1

field ls_buf {}

constructor embed {i_w} {
	set w $i_w

	_init $this

	return $this
}

method _init {} {
	global cursor_ptr M1B use_ttk NS

	set w_files $w.list
	text $w_files \
		-background white \
		-foreground black \
		-borderwidth 0 \
		-highlightthickness 0 \
		-cursor $cursor_ptr \
		-state disabled \
		-wrap none \
		-height 10 \
		-width 70 \
		-xscrollcommand [list $w.sbx set] \
		-yscrollcommand [list $w.sby set]
	rmsel_tag $w_files
	${NS}::scrollbar $w.sbx -orient h -command [list $w_files xview]
	${NS}::scrollbar $w.sby -orient v -command [list $w_files yview]
	$w_files tag conf rblob   -lmargin1 5 -rmargin 1
	$w_files tag conf xblob   -lmargin1 5 -rmargin 1 -foreground green4
	$w_files tag conf symlink -lmargin1 5 -rmargin 1 -foreground cyan4

	${NS}::frame $w.filter
	set w_filter $w.filter.e
	${NS}::entry $w_filter \
		-textvariable @filter \
		-validate key \
		-validatecommand [cb _filter_update %P]
	if {!$use_ttk} {$w_filter configure -borderwidth 1 -relief sunken}
	${NS}::label $w.filter.i \
		-image ::full_browser::img_find
	${NS}::button $w.filter.x \
		-image ::full_browser::img_clear \
		-command [cb _filter_reset]
	${NS}::checkbutton $w.filter.c \
		-text "hidden" \
		-variable @filter_show_dot

	pack $w.filter.c -side right
	pack $w.filter.x -side right
	pack $w.filter.i -side left
	pack $w_filter -side left -fill x -expand 1

	pack $w.filter -anchor w -side top -fill x
	pack $w.sbx -side bottom -fill x
	pack $w.sby -side right -fill y
	pack $w_files -side bottom -fill both -expand 1

	bind $w       <Map> [cb _on_mapped]

	bind $w_files <Button-1>             "[cb _list_click @%x,%y]; break"
	bind $w_files <ButtonRelease-2>      "[cb _list_open @%x,%y]; break"
	bind $w_files <$M1B-ButtonRelease-2> "[cb _list_blame @%x,%y]; break"
	bind $w_files <Up>                   "[cb _list_move] -1; break"
	bind $w_files <Down>                 "[cb _list_move]  1; break"
	bind $w_files <Key-Prior>            "[cb _list_page -1]; break"
	bind $w_files <Key-Next>             "[cb _list_page  1]; break"
	bind $w_files <Left>                 break
	bind $w_files <Right>                break
	bind $w_files <Return>               "[cb _open_selected]; break"
	bind $w_files <$M1B-Return>          "[cb _blame_selected]; break"

	bind $w_filter <Escape>      "[cb _filter_reset]; break"
	bind $w_filter <Up>          "[cb _list_move] -1; break"
	bind $w_filter <Down>        "[cb _list_move]  1; break"
	bind $w_filter <Key-Prior>   "[cb _list_page -1]; break"
	bind $w_filter <Key-Next>    "[cb _list_page  1]; break"
	bind $w_filter <Return>      "[cb _open_selected]; break"
	bind $w_filter <$M1B-Return> "[cb _blame_selected]; break"
	bind $w_filter <Visibility>  [list focus $w_filter]
}

method _reload {} {
	if {$need_reload} {
		set need_reload 0
		_refresh $this
	}
}

method reload {{W {}}} {
	set need_reload 1
	if {[string equal -length [string length $w] $w $W]} {
		_reload $this
	}
}

method reorder_bindtags {} {
	foreach i [list $w_filter $w_files] {
		bindtags $i [list all $i [winfo class $i] .]
	}
}

method _refresh {{_filter {}}} {
	if {$busy} return
	set busy 1
	set ls_buf {}
	set matches [list]

	set pattern {}
	set sep {}
	if {[string length $_filter] == 0} {
		set _filter $filter
	}
	set subs [split $_filter {/}]
	for {set i 0} {$i < [llength $subs]} {} {
		set p [lindex $subs $i]
		append pattern $sep
		incr i
		if {$i == [llength $subs]} {
			append pattern "*"
		}
		append pattern $p
		append pattern "*"
		set sep {/}
	}

	$w_files conf -state normal
	$w_files tag remove in_sel 0.0 end
	$w_files delete 0.0 end
	$w_files conf -state disabled

	set cmd [list ls-files --recurse-submodules -s -z]
	set fd [eval git_read $cmd]
	fconfigure $fd -blocking 0 -translation binary -encoding binary
	fileevent $fd readable [cb _read $fd]
}

method _read {fd} {
	append ls_buf [read $fd]
	set pck [split $ls_buf "\0"]
	set ls_buf [lindex $pck end]

	$w_files conf -state normal
	foreach p [lrange $pck 0 end-1] {
		set tab [string first "\t" $p]
		if {$tab == -1} continue

		set info [split [string range $p 0 [expr {$tab - 1}]] { }]
		scan [lindex $info 0] %o mode
		set path [string range $p [expr {$tab + 1}] end]
		set path [encoding convertfrom $path]

		if {[string length $filter] == 0 || [string match -nocase $pattern $path]} {

			if {$mode == 0120000} {
				set tag symlink
			} elseif {($mode & 0111) != 0} {
				set tag xblob
			} else {
				set tag rblob
			}

			if {[llength $matches] > 0} {
				$w_files insert end "\n"
			}
			$w_files insert end "[escape_path $path]" $tag
			lappend matches $path
		}
	}
	$w_files conf -state disabled

	if {[eof $fd]} {
		close $fd
		set busy 0
		set ls_buf {}
		if {[llength $matches] > 0} {
			$w_files tag add in_sel 1.0 2.0
		}
	}

} ifdeleted {
	catch {close $fd}
}

method _filter_update {P} {
	if {$busy} {return 0}

	if {[regexp {\s} $P]} {
		return 0
	}

	_refresh $this $P
	return 1
}

method _filter_reset {} {
	$w_filter delete 0 end
}

method _list_move {dir} {
	if {$busy} return

	if {[catch {$w_files index in_sel.first}]} {
		return
	}

	set lno [lindex [split [$w_files index in_sel.first] .] 0]
	incr lno $dir

	if {1 > $lno} {set lno 1}
	if {$lno > [llength $matches]} {set lno [llength $matches]}
	$w_files tag remove in_sel 0.0 end
	$w_files tag add in_sel $lno.0 "$lno.0 + 1 line"
	$w_files see $lno.0
}

method _list_page {dir} {
	if {$busy} return

	set page [expr {
		int(
		  ceil(
		    ([lindex [$w_files yview] 1] - [lindex [$w_files yview] 0])
		    * [llength $matches]
		  )
		)}]
	set lno [expr "[lindex [split [$w_files index in_sel.first] .] 0] + $dir * $page"]
	if {1 > $lno} {set lno 1}
	if {$lno > [llength $matches]} {set lno [llength $matches]}
	$w_files tag remove in_sel 0.0 end
	$w_files tag add in_sel $lno.0 [expr {$lno + 1}].0
	$w_files see $lno.0
}

method _list_click {pos} {
	if {$busy} return

	set lno [lindex [split [$w_files index $pos] .] 0]
	focus $w_files

	if {1 <= $lno && $lno <= [llength $matches]} {
		$w_files tag remove in_sel 0.0 end
		$w_files tag add in_sel $lno.0 [expr {$lno + 1}].0
	}
}

method _list_open {pos} {
	if {$busy} return

	# select the file
	_list_click $this $pos

	set lno [lindex [split [$w_files index $pos] .] 0]

	set filename [lindex $matches [expr {$lno - 1}]]
	if {$filename ne {}} {
		open_in_git_editor $filename
	}
}

method _list_blame {pos} {
	if {$busy} return

	# select the file
	#_list_click $this $pos

	set lno [lindex [split [$w_files index $pos] .] 0]

	set filename [lindex $matches [expr {$lno - 1}]]
	if {$filename ne {}} {
		blame_path_in_tab $filename
	}
}

method _open_selected {} {
	if {$busy} return

	if {[catch {$w_files index in_sel.first}]} {
		return
	}

	set lno [lindex [split [$w_files index in_sel.first] .] 0]

	set filename [lindex $matches [expr {$lno - 1}]]
	if {$filename ne {}} {
		open_in_git_editor $filename
	}
}

method _blame_selected {} {
	if {$busy} return

	if {[catch {$w_files index in_sel.first}]} {
		return
	}

	set lno [lindex [split [$w_files index in_sel.first] .] 0]

	set filename [lindex $matches [expr {$lno - 1}]]
	if {$filename ne {}} {
		blame_path_in_tab $filename
	}
}

method _on_mapped {} {
	_reload $this
}

}
