#!/bin/sh
# the next line restarts using wish \
exec wish "$0" "$0" "$@"


#
# xml2rfc.tcl - convert technical memos written using XML to TXT/HTML/NROFF
#
# (c) 1998-01 Invisible Worlds, Inc.
#


if {[catch { package require xml 1.8 } result]} {
    global auto_path

    puts stderr "unable to find the TclXML package, did you install it?"
    puts stderr "here's where i looked for it:"
    foreach d $auto_path {
        puts stderr "    $d"
    }
    flush stderr

    return
}

if {[string compare [package require sgml] 1.6]} {
    global auto_path

    puts stderr \
         "your system has an incompatible version of the Tcl SGML package"
    set path ""
    foreach d $auto_path {
        if {[llength [set p [glob -nocomplain [file join $d tclxml*2*]]]] \
                == 1} {
            set path [lindex $p 0]
            break
        }
    }

    proc look4 {dir} {
        puts stderr "look for a directory called \"$dir\""
        puts stderr "there, you'll find a file called \"pkgIndex.tcl\""
        puts stderr "rename it to \"pkgIndex-bad.tcl\" and try again"
        flush stderr
    }

    if {[string compare $path ""]} {
        return [look4 $path]
    }

    foreach d $auto_path {
        foreach i [glob -nocomplain [file join $d * pkgIndex.tcl]] {
            if {![catch { open $i { RDONLY } } fd]} {
                while {[gets $fd line] >= 0} {
                    if {([string first "package ifneeded sgml" $line] < 0) \
                            || ([string first "package ifneeded sgml 1.6" \
                                        $line] >= 0)} {
                        continue
                    }
                    catch { close $fd }
                    return [look4 [file dirname $i]]
                }
                catch { close $fd }
            }
        }
    }

    puts stderr \
         "the bad news is that i can't figure out where this package is!"
    puts stderr "i've looked in these directories"
    foreach d $auto_path {
        puts stderr "    $d"
    }
    puts stderr "and i can't find it, sorry."

    return
}


#
# top-level parsing
#


global parser
if {![info exists parser]} {
    set parser ""
}

proc xml2rfc {input {output ""} {remote ""}} {
    global errorCode errorInfo
    global parser
    global passno
    global passmax
    global errorP
    global ifile mode ofile
    global stdout
    global remoteP

    if {![string compare [file extension $input] ""]} {
        append input .xml
    }

    set stdin [open $input { RDONLY }]
    set inputD [file dirname [set ifile $input]]

    if {![string compare $output ""]} {
        set output [file rootname $input].txt
    }
    if {[string compare $remote ""]} {
        set ofile $remote
        set remoteP 1
    } else {
        set ofile $output
        set remoteP 0
    }
    set ofile [file rootname [file tail $ofile]]

    if {![string compare $input $output]} {
        error "input and output files must be different"
    }

    if {[file exists [set file [file join $inputD .xml2rfc.rc]]]} {
        source $file
    }

    switch -- [set mode [string range [file extension $output] 1 end]] {
        html -
        nr   -
        txt  {}

        xml {
            set stdout [open $output { WRONLY CREAT TRUNC }]

            puts -nonewline $stdout [prexml [read $stdin] $inputD]

            catch { close $stdout }
            catch { close $stdin }

            return
        }

        default {
            catch { close $stdin }
            error "unsupported output type: $mode"
        }
    }

    set code [catch {
        if {![string compare $parser ""]} {
            global emptyA

            set parser [xml::parser]
            array set emptyA {}

            $parser configure \
                        -elementstartcommand          { begin               } \
                        -elementendcommand            { end                 } \
                        -characterdatacommand         { pcdata              } \
                        -processinginstructioncommand { pi                  } \
                        -xmldeclcommand               { xmldecl             } \
                        -doctypecommand               { doctype             } \
                        -entityreferencecommand       ""                      \
                        -errorcommand                 { unexpected error    } \
                        -warningcommand               { unexpected warning  } \
                        -entityvariable               emptyA                  \
                        -final                        yes                     \
                        -reportempty                  no
        }

        set data [prexml [read $stdin] $inputD $input]

        catch { close $stdin }

        set errorP 0
        set passmax 2
        set stdout ""
        for {set passno 1} {$passno <= $passmax} {incr passno} {
            if {$passno == 2} {
                set stdout [open $output { WRONLY CREAT TRUNC }]
            }
            pass start
            $parser parse $data
            pass end
            if {$errorP} {
                break
            }
        }
    } result]
    set ecode $errorCode
    set einfo $errorInfo

    catch { close $stdout }

    if {$code == 1} {
        set result [around2fl $result]

        catch {
            global stack

            if {[llength $stack] > 0} {
                set text "Context: "
                foreach frame $stack {
                    catch { unset attrs }
                    array set attrs [list av ""]
                    array set attrs [lrange $frame 1 end] 
                    append text "\n    <[lindex $frame 0]"
                    foreach {k v} $attrs(av) {
                        regsub -all {"} $v {&quot;} v
                        append text " $k=\"$v\""
                    }
                    append text ">"
                }
                append result "\n\n$text"
            }
        }
    }

    return -code $code -errorinfo $einfo -errorcode $ecode $result
}

proc xml2txt {input} {
    xml2rfc $input [file rootname $input].txt
}

proc xml2html {input} {
    xml2rfc $input [file rootname $input].html
}

proc xml2nroff {input} {
    return [xml2rfc $input [file rootname $input].nr]
###
    puts stderr "making xml->txt"
    xml2rfc $input [file rootname $input].txt
    file rename -force [file rootname $input].txt  [file rootname $input].orig

    puts stderr "making xml->rf"
    xml2rfc $input [file rootname $input].nr

    puts stderr "making rf->txt"
    exec nroff -ms < [file rootname $input].nr \
       | /usr/users/mrose/docs/fix.pl \
       | sed -e 1,3d \
       > [file rootname $input].txt
}

proc xml2ref {input output} {
    global errorCode errorInfo

    if {![string compare $input $output]} {
        error "input and output files must be different"
    }

    if {[file exists [set file [file join [set inputD [file dirname $input]] \
                                          .xml2rfc.rc]]]} {
        source $file
    }

    set refT [ref::init]
    if {[set code [catch { ref::transform $refT $input } result]]} {
        set ecode $errorCode
        set einfo $errorInfo

        catch { ref::fin $refT }

        return -code $code -errorinfo $einfo -errorcode $ecode $result
    }
    ref::fin $refT

    set stdout [open $output { WRONLY CREAT TRUNC }]

    set code [catch {
        puts -nonewline $stdout $result
        flush $stdout
    } result]
    set ecode $errorCode
    set einfo $errorInfo

    catch { close $stdout }

    return -code $code -errorinfo $einfo -errorcode $ecode $result
}

proc prexml {stream inputD {inputF ""}} {
    global env tcl_platform

    if {[catch { set path $env(XML_LIBRARY) }]} {
        set path [list $inputD]
    }
    switch -- $tcl_platform(platform) {
        windows {
            set c ";"
        }

        default {
            set c ":"
        }
    }
    set path [split $path $c]

    if {[string first "%include." $stream] < 0} {
        set newP 1
    } else {
        set newP 0
    }
    set stream [prexmlaux $newP $stream $inputD $inputF $path]

# because <![CDATA[ ... ]]> isn't supported in TclXML...
    set data ""
    set litN [string length [set litS "<!\[CDATA\["]]
    set litO [string length [set litT "\]\]>"]]
    while {[set x [string first $litS $stream]] >= 0} {
        append data [string range $stream 0 [expr $x-1]]
        set stream [string range $stream [expr $x+$litN] end]
        if {[set x [string first $litT $stream]] < 0} {
            error "missing close to CDATA"
        }
        set y [string range $stream 0 [expr $x-1]]
        regsub -all {&} $y {\&amp;} y
        regsub -all {<} $y {\&lt;}  y
        append data $y
        set stream [string range $stream [expr $x+$litO] end]
    }
    append data $stream

    return $data
}


proc prexmlaux {newP stream inputD inputF path} {
    global fldata

# an MTR hack...

# the old way:
#
# whenever "%include.whatever;" is encountered, act as if the DTD contains
#
#       <!ENTITY % include.whatever SYSTEM "whatever.xml">
#
# this yields a nested (and cheap-and-easy) include facility.
#

# the new way:
#
# <?rfc include='whatever' ?>
#
# note that this occurs *before* the xml parsing occurs, so they aren't hidden
# inside a <![CDATA[ ... ]]> block.
#

    if {$newP} {
        set litS "<?rfc include="
        set litT "?>"
    } else {
        set litS "%include."
        set litT ";"
    }
    set litN [string length $litS]
    set litO [string length $litT]

    set data ""
    set fldata [list [list $inputF [set lineno 1] [numlines $stream]]]
    while {[set x [string first $litS $stream]] >= 0} {
        incr lineno [numlines [set initial \
                                   [string range $stream 0 [expr $x-1]]]]
        append data $initial
        set stream [string range $stream [expr $x+$litN] end]
        if {[set x [string first $litT $stream]] < 0} {
            error "missing close to %include.*"
        }
        set y [string range $stream 0 [expr $x-1]]
        if {$newP} {
            set y [string trim $y]
            if {[set quoteP [string first "'" $y]]} {
                regsub -- {^"([^"]*)"$} $y {\1} y
            } else {
                regsub -- {^'([^']*)'$} $y {\1} y
            }
        }
        if {![regexp -nocase -- {^[a-z0-9.-]+$} $y]} {
            error "invalid include $y"
        }
        set foundP 0
        foreach dir $path {
            if {(![file exists [set file [file join $dir $y]]]) \
                    && (![file exists [set file [file join $dir $y.xml]]])} {
                continue
            }
            set fd [open $file { RDONLY }]
            set include [read $fd]
            catch { close $fd }
            set foundP 1
            break
        }
        if {!$foundP} {
            error "unable to find external file $y.xml"
        }

        set body [string trimleft $include]
        if {([string first "<?XML " [string toupper $body]] == 0) 
                && ([set len [string first "?>" $body]] >= 0)} {
            set start [expr [string length $include]-[string length $body]]
            incr len
            set include [string replace $include $start [expr $start+$len] \
                                [format " %*.*s" $len $len ""]]

            set body [string trimleft $include]
        }
        if {([string first "<!DOCTYPE " [string toupper $body]] == 0) 
                && ([set len [string first ">" $body]] >= 0)} {
            set start [expr [string length $include]-[string length $body]]
            set include [string replace $include $start [expr $start+$len] \
                                [format " %*.*s" $len $len ""]]
        }

        set len [numlines $include]
        set flnew {}
        foreach fldatum $fldata {
            set end [lindex $fldatum 2]
            if {$end >= $lineno} {
                set fldatum [lreplace $fldatum 2 2 [expr $end+$len]]
            }
            lappend flnew $fldatum
        }
        set fldata $flnew
        lappend fldata [list $file $lineno $len]

        set stream $include[string range $stream [expr $x+$litO] end]
    }
    append data $stream

    return $data
}


proc numlines {text} {
    set n [llength [split $text "\n"]]
    if {![string compare [string range $text end end] "\n"]} {
        incr n -1
    }

    return $n
}

proc around2fl {result} {
    global fldata

    if {[regexp -nocase -- { around line ([1-9][0-9]*)} $result x lineno] \
            != 1} {
        return $result
    }

    set file ""
    set offset 0
    set max 0
    foreach fldatum $fldata {
        if {[set start [lindex $fldatum 1]] > $lineno} {
            break
        }
        if {[set new [expr $start+[set len [lindex $fldatum 2]]]] < $max} {
            continue
        }

        if {$lineno <= $new} {
            set file [lindex $fldatum 0]
            set offset [expr $lineno-$start]
        } else {
            incr offset -$len
            set max $new
        }
    }

    set tail " around line $offset"
    if {[string compare $file [lindex [lindex $fldata 0] 0]]} {
        append tail " in $file"
    }
    regsub " around line $lineno" $result $tail result

    return $result
}


#
# XML linkage
#


# globals used in parsing
#
#     counter - used for generating reference numbers
#       depth -  ..
#       elemN - index of current element
#        elem - array, indexed by elemN, having:
#               list of element attributes,
#               plus ".CHILDREN", ".COUNTER", ".CTEXT"/".CLINES", ".NAME",
#                    ".ANCHOR", ".EDITNO"
#      passno - 1 or 2 (or maybe 3, if generating a TOC)
#       stack - the stack of elements, each frame having:
#               { element-name "elemN" elemN "children" { elemN... }
#                 "ctext" yes-or-no }
#        xref - array, indexed by anchor, having:
#               { "type" element-name "elemN" elemN "value" reference-number }

proc pass {tag} {
    global options
    global counter depth elemN elem passno stack xref
    global anchorN
    global elemZ
    global erefs

    switch -- $tag {
        start {
            unexpected notice "pass $passno..."
            if {$passno == 1} {
                catch { unset counter }
                catch { unset depth }
                catch { unset elem }
                catch { unset xref }
                catch { unset erefs }
                set anchorN 0
            }
            set elemN 0
            catch { unset options }
            array set options [list compact    no  \
                                    subcompact no  \
                                    toc        no  \
                                    tocompact  yes \
                                    editing    no  \
                                    emoticonic no  \
                                    private    ""  \
                                    header     ""  \
                                    footer     ""  \
                                    slides     no  \
                                    sortrefs   no  \
                                    symrefs    no  \
                                    background ""]
            normalize_options
            catch { unset stack }
        }

        end {
            set elemZ $elemN
        }
    }
}


# begin element

global required ctexts categories

set required { date       { month year }
               note       { title  }
               section    { title  }
               xref       { target }
               eref       { target }
               iref       { item }
# backwards compatibility...
#               seriesInfo { name value }
             }
          
set ctexts   { title organization street city region code country phone
               facsimile email uri area workgroup keyword xref eref
               seriesInfo }

set categories \
             { {std  "Standards Track" STD
"This document specifies an Internet standards track protocol for the Internet
community, and requests discussion and suggestions for improvements.
Please refer to the current edition of the &quot;Internet Official Protocol
Standards&quot; (STD 1) for the standardization state and status of this
protocol.
Distribution of this memo is unlimited."}

               {bcp      "Best Current Practice" BCP
"This document specifies an Internet Best Current Practice for the Internet
Community, and requests discussion and suggestions for improvements.
Distribution of this memo is unlimited."}

               {info     "Informational" FYI
"This memo provides information for the Internet community.
It does not specify an Internet standard of any kind.
Distribution of this memo is unlimited."}

               {exp      "Experimental" EXP
"This memo defines an Experimental Protocol for the Internet community.
It does not specify an Internet standard of any kind.
Discussion and suggestions for improvement are requested.
Distribution of this memo is unlimited."}

               {historic "Historic" ""
"This memo describes a historic protocol for the Internet community.
It does not specify an Internet standard of any kind.
Distribution of this memo is unlimited."} }

set iprstatus \
             { {full2026
"in full conformance with all provisions of Section 10 of RFC2026."}

               {noDerivativeWorks2026
"in full conformance with all provisions of Section 10 of RFC2026
except that the right to produce derivative works is not granted."}

               {noDerivativeWorksNow
"in full conformance with all provisions of Section 10 of RFC2026
except that the right to produce derivative works is not granted.
(If this document becomes part of an IETF working group activity,
then it will be brought into full compliance with Section 10 of RFC2026.)"}

               {none
"NOT offered in accordance with Section 10 of RFC2026,
and the author does not provide the IETF with any rights other
than to publish as an Internet-Draft."} }

proc begin {name {av {}}} {
    global counter depth elemN elem passno stack xref
    global anchorN
    global options
    global required ctexts categories iprstatus

# because TclXML... quotes attribute values containing "]"
    set kv ""
    foreach {k v} $av {
        lappend kv $k
        regsub -all {\\\[} $v {[} v
        lappend kv $v
    }
    set av $kv

    incr elemN

    if {$passno == 1} {
        set elem($elemN) $av
        array set attrs $av

        foreach { n a } $required {
            switch -- [string compare $n $name] {
                -1 {
                     continue
                }

                0 {
                    foreach v $a {
                        if {[catch { set attrs($v) }]} {
                            unexpected error \
                                "missing $v attribute in $name element"
                        }
                    }
                    break
                }

                1 {
                    break
                }
            }
        }

        switch -- [set type $name] {
            rfc {
                if {![catch { set attrs(category) }]} {
                    if {[lsearch0 $categories $attrs(category)] < 0} {
                        unexpected error \
                            "category attribute unknown: $attrs(category)"
                    }
                    if {(![string compare $attrs(category) historic]) \
                            && (![catch { set attrs(seriesNo) }])} {
                        unexpected error \
                            "historic documents have no document series"
                    }
                }
                if {![catch { set attrs(ipr) }]} {
                    if {[lsearch0 $iprstatus $attrs(ipr)] < 0} {
                        unexpected error \
                            "ipr attribute unknown: $attrs(ipr)"
                    }
                }
                global entities oentities mode nbsp
                if {[ catch { set number $attrs(number) }]} {
                    set number XXXX
                }
                set entities [linsert $oentities 0 "&rfc.number;" $number]
                switch -- $mode {
                    nr
                        -
                    txt {
                        set nbsp "\xa0"
                        set entities [linsert $entities 0 "&nbsp;" $nbsp]
                    }
                }
            }

            back {
                catch { unset depth(section) }
            }

            abstract {
                if {[lsearch0 $stack back] < 0} {
                    set counter(abstract) 1
                }
            }

            section {
                if {[catch { incr depth(section) }]} {
                    set depth(section) 1
                    set counter(section) 0
                }
                set counter(section) \
                         [counting $counter(section) $depth(section)]
                set l [split $counter(section) .]
                if {[lsearch0 $stack back] >= 0} {
                    set type appendix
                    set l [lreplace $l 0 0 \
                                [string index " ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
                                    [lindex $l 0]]]
                }
                set attrs(.COUNTER) [set value [join $l .]]
                if {[catch { set attrs(anchor) }]} {
                    set attrs(anchor) anchor[incr anchorN]
                }
                set attrs(.ANCHOR) $attrs(anchor)
                set elem($elemN) [array get attrs]
            }

            list {
                if {[catch { incr depth(list) }]} {
                    set depth(list) 1
                    set counter(list) 0
                }
            }

            t {
                if {[catch { incr counter(editno) }]} {
                    set counter(editno) 1
                }
                set attrs(.EDITNO) $counter(editno)
                set elem($elemN) [array get attrs]
                if {[lsearch0 $stack list] >= 0} {
                    set counter(list) [counting $counter(list) $depth(list)]
                    set attrs(.COUNTER) $counter(list)
                    set elem($elemN) [array get attrs]
                }
            }

            figure {
                if {[catch { incr counter(figure) }]} {
                    set counter(figure) 1
                }
                set attrs(.COUNTER) [set value $counter(figure)]
                set elem($elemN) [array get attrs]
            }

            preamble
                -
            postamble {
                if {[catch { incr counter(editno) }]} {
                    set counter(editno) 1
                }
                set attrs(.EDITNO) $counter(editno)
                set elem($elemN) [array get attrs]
            }

            reference {
                if {$options(.SYMREFS)} {
                    set value $attrs(anchor)
                } else {
                    if {[catch { incr counter(reference) }]} {
                        set counter(reference) 1
                    }
                    set value $counter(reference)
                }
                set attrs(.COUNTER) $value
                set elem($elemN) [array get attrs]
            }
        }

        if {![catch { set anchor $attrs(anchor) }]} {
            if {![catch { set xref($anchor) }]} {
                unexpected error "anchor attribute already in use: $anchor"
            }
            set xref($anchor) [list type $type elemN $elemN value $value]
        }

        if {$elemN > 1} {
            set frame [lindex $stack end]
            set children [lindex $frame 4]
            lappend children $elemN
            set frame [lreplace $frame 4 4 $children]
            set stack [lreplace $stack end end $frame]
        }
    } else {
        if {0 && (![string compare $passno/$name 2/eref])} {
            array set attrs $elem($elemN)

            if {[catch { incr counter(reference) }]} {
                set counter(reference) 1
            }
            set attrs(.COUNTER) $counter(reference)
            set elem($elemN) [array get attrs]
        }
        switch -- $name {
            rfc {
                pass2begin_$name $elemN
            }

            front
                -
            abstract
                -
            note
                -
            section
                -
            t
                -
            list
                -
            figure
                -
            preamble
                -
            postamble
                -
            xref
                -
            eref
                -
            iref
                -
            vspace
                -
            back {
                if {[lsearch0 $stack references] < 0} {
                    pass2begin_$name $elemN
                }
            }
        }
    }

    if {[lsearch -exact $ctexts $name] >= 0} {
        set ctext yes
        if {$passno == 1} {
            set attrs(.CTEXT) ""
            set elem($elemN) [array get attrs]
        }
    } else {
        set ctext no
    }
    lappend stack [list $name elemN $elemN children "" ctext $ctext av $av]
}

proc counting {tcount tdepth} {
    set x [llength [set l [split $tcount .]]]

    if {$x > $tdepth} {
        set l [lrange $l 0 [expr $tdepth-1]]
        set x $tdepth
    } elseif {$x < $tdepth} {
        lappend l 0
        incr x
    }
    incr x -1
    set l [lreplace $l $x $x [expr [lindex $l $x]+1]]
    return [join $l .]
}

# end element

proc end {name} {
    global counter depth elemN elem passno stack xref

    set frame [lindex $stack end]
    set stack [lreplace $stack end end]

    array set av [lrange $frame 1 end]
    set elemX $av(elemN)

    if {$passno == 1} {
        array set attrs $elem($elemX)

        set attrs(.CHILDREN) $av(children)
        set attrs(.NAME) $name
        set elem($elemX) [array get attrs]

        switch -- $name {
            section {
                incr depth(section) -1
            }

            list {
                if {[incr depth(list) -1] == 0} {
                    set counter(list) 0
                }
            }
        }

        return
    }

    switch -- $name {
        rfc
            -
        front
            -
        t
            -
        list
            -
        figure
            -
        preamble
            -
        postamble {
            if {[lsearch0 $stack references] < 0} {
                pass2end_$name $elemX
            }
        }
    }
}


# character data

proc pcdata {text} {
    global counter depth elemN elem passno stack xref
    global mode

    if {[string length [set chars [string trim $text]]] <= 0} {
        return
    }

    regsub -all "\r" $text "\n" text

    set frame [lindex $stack end]

    if {$passno == 1} {
        array set av [lrange $frame 1 end]

        set elemX $av(elemN)
        array set attrs $elem($elemX)
        if {![string compare $av(ctext) yes]} {
            append attrs(.CTEXT) $chars
        } else {
            set attrs(.CLINES) [llength [split $text "\n"]]
        }
        set elem($elemX) [array get attrs]

        return
    }

    if {[lsearch0 $stack references] >= 0} {
        return
    }

    switch -- [lindex $frame 0] {
        artwork {
            set pre 1
        }

        t
            -
        preamble
            -
        postamble {
            set pre 0
        }

        default {
            return
        }
    }

    pcdata_$mode $text $pre
}


# processing instructions

proc pi {args} {
    global options
    global counter depth elemN elem passno stack xref

    switch -- [lindex $args 0]/[llength $args] {
        xml/2 {
            if {([string first "version=\"1.0\"" [lindex $args 1]] < 0) \
                    && ([string first "version='1.0'" [lindex $args 1]] < 0)} {
                unexpected error "unexpected <?xml ...?>"
            }
        }

        DOCTYPE/4 {
            if {[info exists stack]} {
                return
            }

            if {![string match "-public -system rfc*.dtd" \
                         [lrange $args 1 end]]} {
                unexpected error "unexpected DOCTYPE: [lrange $args 1 end]"
            }
        }

        rfc/2 {
            set text [string trim [lindex $args 1]]
            if {[catch { 
                if {[llength [set params [split $text =]]] != 2} {
                    error ""
                }
                set key [lindex $params 0]
                set value [lindex $params 1]
                if {[string first "'" $value]} {
                    regsub -- {^"([^"]*)"$} $value {\1} value
                } else {
                    regsub -- {^'([^']*)'$} $value {\1} value
                }
                if {![string compare $key include]} {
                    return
                }
                set options($key) $value
            }]} {
                unexpected error "invalid rfc instruction: $text"
            }
            normalize_options
        }

        default {
            set text [join $args " "]
            unexpected warning "unknown PI: $text"
        }
    }
}

proc normalize_options {} {
    global passmax
    global options
    global mode
    global remoteP

    if {$remoteP} {
        set options(slides) no
    }
    foreach {o O} [list compact    .COMPACT    \
                        subcompact .SUBCOMPACT \
                        toc        .TOC        \
                        tocompact  .TOCOMPACT  \
                        editing    .EDITING    \
                        emoticonic .EMOTICONIC \
                        symrefs    .SYMREFS    \
                        sortrefs   .SORTREFS   \
                        slides     .SLIDES] {
        switch -- $options($o) {
            yes - true - 1 {
                set options($O) 1
            }

            default {
                set options($O) 0
            }
        }
    }
    foreach {o O} [list private .PRIVATE \
                        header  .HEADER  \
                        footer  .FOOTER] {
        set options($O) 0
        if {[string compare $options($o) ""]} {
            set options($O) 1
        }
    }
    switch -- $mode {
        nr  -
        txt {
            if {$options(.TOC)} {
                set passmax 3
            }
        }

        html {
            if {$options(.SLIDES)} {
                set passmax 3
            }
        }
    }
    if {!$options(.COMPACT)} {
        set options(.SUBCOMPACT) 0
    }
    if {$options(.PRIVATE)} {
        set options(.HEADER) 1
        set options(.FOOTER) 1
    }
}


# xml and dtd declaration

proc xmldecl {version encoding standalone} {
    if {[string compare $version 1.0]} {
        unexpected error "invalid XML version: $version"
    }
}


proc doctype {element public system internal} {
    global counter depth elemN elem passno stack xref

    if {[info exists stack]} {
        return
    }

    if {[string compare $element rfc] \
            || [string compare $public ""] \
            || (![string match "rfc*.dtd" $system])} {
        unexpected error "invalid DOCTYPE: $element+$public+$system+$internal"
    }
}


# the unexpected ...

proc unexpected {args} {
    global guiP

    set text [join [lrange $args 1 end] " "]

    switch -- [set type [lindex $args 0]] {
        error {
            global errorP

            set errorP 1
            return -code error $text
        }

        notice {
            if {$guiP == -1} {
                puts stdout $text
            }
        }

        default {
            switch -- $guiP {
                1 {
                    tk_dialog .unexpected "xml2rfc: $type" $text $type 0 OK
                }

                -1 {
                    puts stdout "$type: $text"
                }
            }
        }
    }
}


#
# specific elements
#


# the whole document

global copylong

set copylong {
"Copyright (C) The Internet Society (%YEAR%). All Rights Reserved."

"This document and translations of it may be copied and furnished to
others, and derivative works that comment on or otherwise explain it
or assist in its implementation may be prepared, copied, published and
distributed, in whole or in part, without restriction of any kind,
provided that the above copyright notice and this paragraph are
included on all such copies and derivative works. However, this
document itself may not be modified in any way, such as by removing
the copyright notice or references to the Internet Society or other
Internet organizations, except as needed for the purpose of
developing Internet standards in which case the procedures for
copyrights defined in the Internet Standards process must be
followed, or as required to translate it into languages other than
English."

"The limited permissions granted above are perpetual and will not be
revoked by the Internet Society or its successors or assigns."

"This document and the information contained herein is provided on an
&quot;AS IS&quot; basis and THE INTERNET SOCIETY AND THE INTERNET ENGINEERING
TASK FORCE DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO ANY WARRANTY THAT THE USE OF THE INFORMATION
HEREIN WILL NOT INFRINGE ANY RIGHTS OR ANY IMPLIED WARRANTIES OF
MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE."
}

global funding

set funding \
"Funding for the RFC Editor function is currently provided by the
Internet Society."


proc pass2begin_rfc {elemX} {
    global counter depth elemN elem passno stack xref
    global options copyrightP

    array set attrs [list number ""     obsoletes "" updates "" \
                          category info seriesNo  "" ipr     ""]
    array set attrs $elem($elemX)
    set elem($elemX) [array get attrs]

    if {(!$options(.PRIVATE)) \
            && (![string compare $attrs(number) ""]) \
            && (![string compare $attrs(ipr) ""])} {
        unexpected error \
                   "rfc element needs either a number or an ipr attribute"
    }
    if {![string compare $attrs(ipr) none]} {
        set copyrightP 0
    } else {
        set copyrightP 1
    }
}

proc pass2end_rfc {elemX} {
    global counter depth elemN elem passno stack xref
    global elemZ
    global mode
    global copylong

    array set attrs $elem($elemX)

    set front [find_element front $attrs(.CHILDREN)]
    array set fv $elem($front)

    set date [find_element date $fv(.CHILDREN)]
    array set dv $elem($date)

    regsub -all %YEAR% $copylong $dv(year) copying

    if {![catch { set who $attrs(disclaimant) }]} {
        lappend copying \
"%WHO% expressly disclaims any and all warranties regarding this 
contribution including any warranty that (a) this contribution does 
not violate the rights of others, (b) the owners, if any, of other 
rights in this contribution have been informed of the rights and 
permissions granted to IETF herein, and (c) any required 
authorizations from such owners have been obtained.
This document and the information contained herein is provided on 
an &quot;AS IS&quot; basis and %UWHO% DISCLAIMS ALL WARRANTIES, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTY THAT THE USE 
OF THE INFORMATION HEREIN WILL NOT INFRINGE ANY RIGHTS OR ANY 
IMPLIED WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR 
PURPOSE." \
 \
"IN NO EVENT WILL %UWHO% BE LIABLE TO ANY OTHER PARTY INCLUDING 
THE IETF AND ITS MEMBERS FOR THE COST OF PROCURING SUBSTITUTE GOODS 
OR SERVICES, LOST PROFITS, LOSS OF USE, LOSS OF DATA, OR ANY 
INCIDENTAL, CONSEQUENTIAL, INDIRECT, OR SPECIAL DAMAGES WHETHER 
UNDER CONTRACT, TORT, WARRANTY, OR OTHERWISE, ARISING IN ANY WAY 
OUT OF THIS OR ANY OTHER AGREEMENT RELATING TO THIS DOCUMENT, 
WHETHER OR NOT SUCH PARTY HAD ADVANCE NOTICE OF THE POSSIBILITY OF 
SUCH DAMAGES."

        regsub -all %WHO% $copying $who copying    
        regsub -all %UWHO% $copying [string toupper $who] copying
    }

    array set index ""
    for {set elemY 1} {$elemY <= $elemZ} {incr elemY} {
        catch { unset iv }
        array set iv $elem($elemY)

        if {[string compare $iv(.NAME) iref]} {
            continue
        }
        lappend index($iv(item)+$iv(subitem)) $iv(.ANCHOR)
    }
    set items [lsort -dictionary [array names index]]

    set irefs ""
    set L ""
    set K ""
    foreach item $items {
        set iref ""
        foreach {key subkey} [split $item +] { break }
        if {[string compare [set c [string toupper [string index $key 0]]] \
                    $L]} {
            lappend iref [set L $c]
            set K ""
        } else {
            lappend iref ""
        }
        if {[string compare $key $K]} {
            lappend iref [set K $key]
        } else {
            lappend iref ""
        }
        lappend iref $subkey
        lappend iref $index($item)
        lappend irefs $iref
    }


    set attrs(.ANCHOR) [rfc_$mode $irefs $copying]
    set elem($elemX) [array get attrs]
}


# the front (either for the rfc or a reference)

global copyshort idinfo

set copyshort \
"Copyright (C) The Internet Society (%YEAR%). All Rights Reserved."

set idinfo {
    {
"This document is an Internet-Draft and is %IPR%"

"Internet-Drafts are working documents of the Internet Engineering
Task Force (IETF), its areas, and its working groups.
Note that other groups may also distribute working documents as
Internet-Drafts."

"Internet-Drafts are draft documents valid for a maximum of six months
and may be updated, replaced, or obsoleted by other documents at any time.
It is inappropriate to use Internet-Drafts as reference material or to cite
them other than as \"work in progress.\""

"The list of current Internet-Drafts can be accessed at
http://www.ietf.org/ietf/1id-abstracts.txt."

"The list of Internet-Draft Shadow Directories can be accessed at
http://www.ietf.org/shadow.html."

"This Internet-Draft will expire on %EXPIRES%."
    }

    {
"This document is an Internet-Draft and is %IPR%"

"Internet-Drafts are working documents of the Internet Engineering
Task Force (IETF), its areas, and its working groups.
Note that other groups may also distribute working documents as
Internet-Drafts."

"Internet-Drafts are draft documents valid for a maximum of six months
and may be updated, replaced, or obsoleted by other documents at any time.
It is inappropriate to use Internet-Drafts as reference material or to cite
them other than as \"work in progress.\""

"The list of current Internet-Drafts can be accessed at
<a href='http://www.ietf.org/ietf/1id-abstracts.txt'>http://www.ietf.org/ietf/1id-abstracts.txt</a>."

"The list of Internet-Draft Shadow Directories can be accessed at
<a href='http://www.ietf.org/shadow.html'>http://www.ietf.org/shadow.html</a>."

"This Internet-Draft will expire on %EXPIRES%."
    }
}

proc pass2begin_front {elemX} {
    global counter depth elemN elem passno stack xref
    global elemZ
    global options
    global ifile mode ofile
    global categories copyshort idinfo iprstatus

    array set attrs $elem($elemX)

    set title [find_element title $attrs(.CHILDREN)]
    array set tv [list abbrev ""]
    array set tv $elem($title)
    if {([string length $tv(.CTEXT)] > 42) \
            && (![string compare $tv(abbrev) ""])} {
        unexpected error "title element needs an abbrev attribute"
    }
    if {![string compare $tv(abbrev) ""]} {
        set tv(abbrev) $tv(.CTEXT)
    }
    set title [list $tv(.CTEXT)]

    set date [find_element date $attrs(.CHILDREN)]
    array set dv $elem($date)
    if {[catch { set dv(day) }]} {
        set now [clock seconds]
        set three [clock format $now -format "%B %Y %d"]
        if {(![string compare $dv(month) [lindex $three 0]]) \
                && (![string compare $dv(year) [lindex $three 1]])} {
            set dv(day) [string trimleft [lindex $three 2] 0]
        }
    }

    array set rv $elem(1)
    catch { set ofile $rv(docName) }

    if {$options(.PRIVATE)} {
        lappend left $options(private)

        set status ""
    } else {
        lappend left "Network Working Group"
        if {[string compare $rv(number) ""]} {
            lappend left "Request for Comments: $rv(number)"

            if {[string compare $rv(obsoletes) ""]} {
                lappend left "Obsoletes: $rv(obsoletes)"
            }
            if {[string compare $rv(updates) ""]} {
                lappend left "Updates: $rv(updates)"
            }
            set cindex [lsearch0 $categories $rv(category)]
            if {[string compare $rv(seriesNo) ""]} {
                lappend left \
                        "[lindex [lindex $categories $cindex] 2]: $rv(seriesNo)"
            }
            set category [lindex [lindex $categories $cindex] 1]
            lappend left "Category: $category"
            set status [list [lindex [lindex $categories $cindex] 3]]
        } else {
            if {![info exists counter(abstract)]} {
                unexpected error "I-D missing abstract"
            }

            lappend left "Internet-Draft"
            if {[catch { set day $dv(day) }]} {
                set day 1
            }
            set secs [clock scan "$dv(month) $day, $dv(year)" -gmt true]
            incr secs [expr (182*86400)+43200]
            set day [string trimleft \
                            [clock format $secs -format "%d" -gmt true] 0]
            set expires [clock format $secs -format "%B $day, %Y" -gmt true]
            lappend left "Expires: $expires"
            set category "Expires $expires"
            if {![string compare $mode html]} {
                set iindex 1
            } else {
                set iindex 0
            }
            set status [lindex $idinfo $iindex]
            regsub -all %IPR% $status \
                   [lindex [lindex $iprstatus \
                                   [lsearch0 $iprstatus $rv(ipr)]] 1] status
            regsub -all %EXPIRES% $status $expires status
        }
    }

    set authors ""
    set names ""
    foreach child [find_element author $attrs(.CHILDREN)] {
        array set av [list initials "" surname "" fullname ""]
        array set av $elem($child)

        set organization [find_element organization $av(.CHILDREN)]
        array set ov [list abbrev ""]
        array set ov $elem($organization)
        if {![string compare $ov(abbrev) ""]} {
            set ov(abbrev) $ov(.CTEXT)
        }

        if {[string compare $av(initials) ""]} {
            set av(initials) [lindex [split $av(initials) .] 0].
        }
        set av(abbrev) "$av(initials) $av(surname)"
        if {[string length $av(abbrev)] == 1} {
            set av(abbrev) ""
            lappend names $ov(abbrev)
        } else {
            lappend names $av(surname)
        }
        set authors [linsert $authors 0 [list $av(abbrev) $ov(abbrev)]]
    }

    set lastO ""
    set right ""
    foreach author $authors {
        if {[string compare [set value [lindex $author 1]] $lastO]} {
            set right [linsert $right 0 [set lastO $value]]
        }
        if {[string compare [set value [lindex $author 0]] ""]} {
            set right [linsert $right 0 $value]
        }
    }
    set day ""
    if {(![string compare $rv(number) ""]) \
            && (![catch { set day $dv(day) }])} {
        set day "$day, "
    }
    lappend right "$dv(month) $day$dv(year)"

    if {$options(.HEADER)} {
        lappend top $options(header)
    } elseif {[string compare $rv(number) ""]} {
        lappend top "RFC $rv(number)"
    } else {
        lappend top "Internet-Draft"
        lappend title $ofile
    }
    lappend top $tv(abbrev)
    lappend top "$dv(month) $dv(year)"

    switch -- [llength $names] {
        1 {
            lappend bottom [lindex $names 0]
        }

        2 {
            lappend bottom "[lindex $names 0] &amp; [lindex $names 1]"
        }

        default {
            lappend bottom "[lindex $names 0], et al."
        }
    }
    if {$options(.FOOTER)} {
        lappend bottom $options(footer)
    } else {
        lappend bottom $category
    }

    regsub -all %YEAR% $copyshort $dv(year) copying

    front_${mode}_begin $left $right $top $bottom $title $status $copying
}

proc pass2end_front {elemX} {
    global counter depth elemN elem passno stack xref
    global elemZ
    global options copyrightP
    global mode

    set toc ""
    set refs 0
    set irefP 0
    if {$options(.TOC)} {
        set last ""
        for {set elemY 1} {$elemY <= $elemZ} {incr elemY} {
            catch { unset cv }
            array set cv $elem($elemY)

            switch -- $cv(.NAME) {
                rfc {
                    if {(!$options(.PRIVATE)) && $copyrightP} {
                        if {[catch { set anchor $cv(.ANCHOR) }]} {
                            set anchor rfc.copyright
                            set label "&#167;"
                        } else {
                            set label ""
                        }
                        set last [list $label "Full Copyright Statement" \
                                       $anchor]
                    }
                }

                section {
                    if {[string first . [set label $cv(.COUNTER)]] < 0} {
                        append label .
                    }
                    lappend toc [list $label $cv(title) $cv(.ANCHOR)]
                }

                back {
                    if {[catch { set anchor $cv(.ANCHOR) }]} {
                        set anchor rfc.authors
                        set label "&#167;"
                    } else {
                        set label ""
                    }
                    array set fv $elem(2)
                    set n [llength [find_element author $fv(.CHILDREN)]]
                    if {$n == 1} {
                        set title "Author's Address"
                    } else {
                        set title "Authors' Addresses"
                    }
                    lappend toc [list $label $title $anchor]
                }

                references {
                    if {[catch { set anchor $cv(.ANCHOR) }]} {
                        set anchor rfc.references[incr refs]
                        set label "&#167;"
                    } else {
                        set label ""
                    }
                    if {[catch { set title $cv(title) }]} {
                        set title References
                    }
                    set toc [linsert $toc [expr [llength $toc]-1] \
                                     [list $label $title $anchor]]
                }

                iref {
                    set irefP 1
                }
            }
        }
        if {[string compare $last ""]} {
            lappend toc $last
        }
    }

    front_${mode}_end $toc $irefP
}

# the abstract/note elements

proc pass2begin_abstract {elemX} {
    global mode
    abstract_$mode
}

proc pass2begin_note {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    set d 0
    foreach frame $stack {
        if {![string compare [lindex $frame 0] note]} {
            incr d
        }
    }

    array set attrs $elem($elemX)

    note_$mode $attrs(title) $d
}

# the section element

proc pass2begin_section {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list anchor ""]
    array set attrs $elem($elemX)

    if {[lsearch0 $stack section] < 0} {
        set top 1
    } else {
        set top 0
    }

    set prefix ""
    set s $attrs(.COUNTER)
    if {$top} {
        append s .
    }
    if {([lsearch0 $stack back] >= 0) && ($top)} {
        set prefix "Appendix "
    }
    set title $attrs(title)

    set lines 0
    if {[llength $attrs(.CHILDREN)] > 0} {
        set elemY [lindex $attrs(.CHILDREN) 0]
        array set cv $elem($elemY)

        if {![string compare $cv(.NAME) figure]} {
            set lines [pass2begin_figure $elemY 1]
        }
    }

    set attrs(.ANCHOR) \
        [section_$mode $prefix$s $top $title $lines $attrs(anchor)]

    set elem($elemX) [array get attrs]
}


# the t element

proc pass2begin_t {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list .COUNTER "" style "" hangText "" hangIndent ""]
    array set attrs $elem($elemX)
    set elem($elemX) [array get attrs]

    if {[string compare $attrs(.COUNTER) ""]} {
        set frame [lindex $stack end]
        array set av [lrange $frame 1 end]

        set elemY $av(elemN)
        array set av $elem($elemY)

        set attrs(hangIndent) $av(hangIndent) 
        if {![string compare [set attrs(style) $av(style)] format]} {
            set attrs(style) hanging
            set format $av(format)

            if {![string compare $attrs(hangText) ""]} {
                set attrs(hangText) [format $format [incr counter($format)]]
            }
        }
        set elem($elemX) [array get attrs]
    }

    t_$mode begin $attrs(.COUNTER) $attrs(style) $attrs(hangText) \
            $attrs(.EDITNO)
}

proc pass2end_t {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs $elem($elemX)

    t_$mode end $attrs(.COUNTER) $attrs(style) $attrs(hangText) ""
}

# the list element

proc pass2begin_list {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    set style empty
    set format ""
    set hangIndent 0
    foreach frame $stack {
        if {[string compare [lindex $frame 0] list]} {
            continue
        }
        array set av [lrange $frame 1 end]

        set elemY $av(elemN)
        array set av $elem($elemY)

        set style $av(style)
        set format $av(format)
        set hangIndent $av(hangIndent)
    }
    array set attrs $elem($elemX)
    catch { set hangIndent $attrs(hangIndent) }
    set attrs(hangIndent) $hangIndent
    catch {
        if {[string first "format " [set style $attrs(style)]]} {
            set format $attrs(format)
        } else {
            set style format
            if {[string compare \
                        [set format [string trimleft \
                                            [string range $attrs(style) 7 \
                                            end]]] ""]} {
                if {[set x [string first "%d" $format]] < 0} {
                    unexpected error "missing %d in format style"
                }
                if {[string first "%d" [string range $format $x end]] > 0} {
                    unexpected error "too many %d's in format style"
                }
                if {![info exists counter($format)]} {
                    set counter($format) 0
                }
            } else {
                set style hanging
                set format ""
            }
        }
    }
    array set attrs [list style $style format $format]
    set elem($elemX) [array get attrs]

    set counters ""
    set hangText ""
    foreach child [find_element t $attrs(.CHILDREN)] {
        array set tv $elem($child)

        lappend counters $tv(.COUNTER)
        catch { set hangText $tv(hangText) }
    }

    list_$mode begin $counters $attrs(style) $attrs(hangIndent) $hangText
}

proc pass2end_list {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs $elem($elemX)

    list_$mode end "" $attrs(style) "" ""
}


# the figure element

proc pass2begin_figure {elemX {internal 0}} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list anchor "" title ""]
    array set attrs $elem($elemX)

    set lines 0
    foreach p {preamble postamble} {
        if {[llength [find_element $p $attrs(.CHILDREN)]] == 1} {
            incr lines 3
        }
    }
    if {$lines > 5} {
        set lines 5
    }

    set artwork [find_element artwork $attrs(.CHILDREN)]
    array set av [list src ""]
    array set av $elem($artwork)

# if artwork is empty!
    catch { incr lines $av(.CLINES) }

    if {$internal} {
        return $lines
    }

    figure_$mode begin $lines $attrs(anchor) $av(src) $attrs(title)
}

proc pass2end_figure {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list anchor "" title ""]
    array set attrs $elem($elemX)

    figure_$mode end "" $attrs(anchor) "" $attrs(title)
}


# the preamble/postamble elements

proc pass2begin_preamble {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs $elem($elemX)

    preamble_$mode begin $attrs(.EDITNO)
}

proc pass2end_preamble {elemX} {
    global mode

    preamble_$mode end
}

proc pass2begin_postamble {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs $elem($elemX)

    postamble_$mode begin $attrs(.EDITNO)
}

proc pass2end_postamble {elemX} {
    global mode

    postamble_$mode end
}


# the xref element

proc pass2begin_xref {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

# pageno is ignored for now...
    array set attrs [list pageno false]
    array set attrs $elem($elemX)

    set anchor $attrs(target)
    xref_$mode $attrs(.CTEXT) $xref($anchor) $anchor
}


# the eref element

proc pass2begin_eref {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs $elem($elemX)

    if {$passno == 2} {
        if {![info exists counter(reference)]} {
            set counter(reference) 0
        }

        if {([string first "#" $attrs(target)] < 0) \
                && ([string compare $attrs(.CTEXT) $attrs(target)])} {
            switch -- $mode {
                nr  -
                txt {
                    incr counter(reference)
                }
            }
        }
        set attrs(.COUNTER) $counter(reference)
        set elem($elemX) [array get attrs]
    }

    eref_$mode $attrs(.CTEXT) $attrs(.COUNTER) $attrs(target)
}


# the iref element

proc pass2begin_iref {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list subitem ""]
    array set attrs $elem($elemX)

    set attrs(.ANCHOR) [iref_$mode $attrs(item) $attrs(subitem)]

    set elem($elemX) [array get attrs]
}


# the vspace element

proc pass2begin_vspace {elemX} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list blankLines 0]
    array set attrs $elem($elemX)
    set elem($elemX) [array get attrs]

    vspace_$mode $attrs(blankLines)
}


# the references/reference elements

# we intercept the back element so we can put the Author's addresses
# after the References section (if any) and before any Appendices

proc pass2begin_back {elemX} {
    global counter depth elemN elem passno stack xref
    global mode
    global erefs

    array set attrs $elem($elemX)

    if {[llength [set children [find_element references $attrs(.CHILDREN)]]] \
            == 1} {
        set erefP 1
    } else {
        set erefP 0
    }
    foreach child $children {
        pass2begin_references $child $erefP
    }
    if {(!$erefP) && ([array size erefs] > 0)} {
        erefs_$mode URIs
    }

    array set fv $elem(2)

    set authors ""
    foreach child [find_element author $fv(.CHILDREN)] {
        array set av [list initials "" surname "" fullname ""]
        array set av $elem($child)

        set organization [find_element organization $av(.CHILDREN)]
        array set ov [list abbrev ""]
        array set ov $elem($organization)

        set block1 ""
        if {[string compare $av(fullname) ""]} {
            lappend block1 $av(fullname)
        }
        if {[string compare $ov(.CTEXT) ""]} {
            lappend block1 $ov(.CTEXT)
        }

        set address [find_element address $av(.CHILDREN)]
        set block2 ""
        if {[llength $address] == 1} {
            array set bv $elem($address)

            set postal [find_element postal $bv(.CHILDREN)]
            if {[llength $postal] == 1} {
                array set pv $elem($postal)

                foreach street [find_element street $pv(.CHILDREN)] {
                    array set sv $elem($street)
    
                    lappend block1 $sv(.CTEXT)
                }

                set s ""
                foreach e {city region code} t {"" ", " "  "} {
                    set f [find_element $e $pv(.CHILDREN)]
                    if {[llength $f] == 1} {
                        catch { unset fv }
                        array set fv $elem($f)
    
                        if {[string compare $s ""]} {
                            append s $t
                        }
                        append s $fv(.CTEXT)
                    }
                }
                if {[string compare $s ""]} {
                    lappend block1 $s
                }
                set f [find_element country $pv(.CHILDREN)]
                if {[llength $f] == 1} {
                    catch { unset fv }
                    array set fv $elem($f)
    
                    lappend block1 $fv(.CTEXT)
                }
            }

            set block2 ""
            foreach e {phone facsimile email uri} {
                set f [find_element $e $bv(.CHILDREN)]
                if {[llength $f] == 1} {
                    catch { unset fv }
                    array set fv $elem($f)

                    lappend block2 [list $e $fv(.CTEXT)]
                }
            }
        }

        lappend authors [list $block1 $block2]
    }

    set attrs(.ANCHOR) [back_$mode $authors]
    set elem($elemX) [array get attrs]
}

proc pass2begin_references {elemX erefP} {
    global counter depth elemN elem passno stack xref
    global mode
    global options

    array set attrs [list title References]
    array set attrs $elem($elemX)

    set attrs(.ANCHOR) [references_$mode begin $attrs(title)]
    set elem($elemX) [array get attrs]
    set children [find_element reference $attrs(.CHILDREN)]
    if {$options(.SORTREFS)} {
        set children [lsort -command sort_references $children]
    }
    set width 0
    foreach child $children {

        array set x $elem($child)
        if {[set y [string length $x(.COUNTER)]] > $width} {
            set width $y
        }

        unset x
    }
    foreach child $children {
        pass2begin_reference $child $width
    }
    references_$mode end "" $erefP
}

proc sort_references {elemX elemY} {
    global counter depth elemN elem passno stack xref

    array set attrX $elem($elemX)
    array set attrY $elem($elemY)
    return [string compare $attrX(anchor) $attrY(anchor)]
}

proc pass2begin_reference {elemX width} {
    global counter depth elemN elem passno stack xref
    global mode

    array set attrs [list anchor "" target "" target2 ""]
    array set attrs $elem($elemX)

    set front [find_element front $attrs(.CHILDREN)]
    array set fv $elem($front)

    set childN [llength [set children [find_element author $fv(.CHILDREN)]]]

    set childA 0
    foreach child [find_element author $fv(.CHILDREN)] {
        incr childA

        array set av [list initials "" surname "" fullname ""]
        array set av $elem($child)

        set organization [find_element organization $av(.CHILDREN)]
        array set ov [list .CTEXT "" abbrev ""]
        if {[string compare $organization ""]} {
            array set ov $elem($organization)
            if {![string compare $ov(abbrev) ""]} {
                set ov(abbrev) $ov(.CTEXT)
            }
        }

        set mref ""
        set uref ""
        set address [find_element address $av(.CHILDREN)]
        if {[llength $address] == 1} {
            array set bv $elem($address)

            foreach {k v p} {email mref mailto: uri uref ""} {
                set u [find_element $k $bv(.CHILDREN)]
                if {[llength $u] == 1} {
                    catch { unset uv }
                    array set uv $elem($u)

                    set $v $p$uv(.CTEXT)
                }
            }
        }
        if {![string compare $mref ""]} {
            set mref $uref
        } elseif {![string compare $uref ""]} {
            set uref $mref
        }

        if {[string compare $av(initials) ""]} {
            set av(initials) [lindex [split $av(initials) .] 0].
        }
        if {($childA > 1) && ($childA == $childN)} {
            set av(abbrev) "$av(initials) $av(surname)"
        } else {
            set av(abbrev) "$av(surname), $av(initials)"
        }
        if {[string length $av(abbrev)] == 2} {
            lappend names [list $ov(.CTEXT) $uref]
        } else {
            lappend names [list $av(abbrev) $mref]
        }
    }
    
    set title [find_element title $fv(.CHILDREN)]

    array set tv [list abbrev ""]
    array set tv $elem($title)
    set title $tv(.CTEXT)

    set series ""
    foreach child [find_element seriesInfo $attrs(.CHILDREN)] {
# backwards compatibility...
        array set sv $elem($child)
        if {([info exists sv(name)]) && ([info exists sv(value)])} {
            lappend series "$sv(name) $sv(value)"
        } else {
            lappend series $sv(.CTEXT)
        }
    }

    set date [find_element date $fv(.CHILDREN)]
    array set dv $elem($date)
    if {[string compare $dv(month) ""]} {
        set date "$dv(month) $dv(year)"
    } else {
        set date $dv(year)
    }

    reference_$mode $attrs(.COUNTER) $names $title $series $date \
                    $attrs(anchor) $attrs(target) $attrs(target2) $width
}

proc find_element {name children} {
    global counter depth elemN elem passno stack xref

    set result ""
    foreach child $children {
        array set attrs $elem($child)

        if {![string compare $attrs(.NAME) $name]} {
            lappend result $child
        }
    }

    return $result
}

# could use "lsearch -glob" followed by a "string compare", but there are
# some amusing corner cases with that...

proc lsearch0 {list exact} {
    set x 0
    foreach elem $list {
        if {![string compare [lindex $elem 0] $exact]} {
            return $x
        }
        incr x
    }

    return -1
}


#
# text output
#


proc rfc_txt {irefs copying} {
    global options copyrightP
    global funding
    global header footer lineno pageno blankP
    global indexpg

    end_page_txt

    if {[llength $irefs] > 0} {
        set indexpg $pageno

        write_line_txt "Index"

        foreach iref $irefs {
            foreach {L item subitem pages} $iref { break }

            if {[string compare $L ""]} {
                write_line_txt ""
                write_line_txt $L           
            }

            if {[string compare $item ""]} {
                write_text_txt $item
                if {[string compare $subitem ""]} {
                    flush_text
                    write_text_txt "   $subitem"
                }
            } else {
                write_text_txt "   $subitem"
            }

            set s "  "
            foreach page $pages {
                write_text_txt "$s$page"
                set s ", "
            }
            flush_text  
        }

        end_page_txt
    }

    if {(!$options(.PRIVATE)) && $copyrightP} {
        set result $pageno

        write_line_txt "Full Copyright Statement"

        foreach para $copying {
            write_line_txt ""
            pcdata_txt $para
        }
        write_line_txt ""

        if {![have_lines 4]} {
            end_page_txt
        }
        write_line_txt "Acknowledgement"
        write_line_txt ""
        pcdata_txt $funding

        end_page_txt
    } else {
        set result ""
    }

    return $result
}

proc front_txt_begin {left right top bottom title status copying} {
    global options copyrightP
    global ifile mode ofile
    global header footer lineno pageno blankP
    global eatP
    global passno indexpg

    set header [three_parts $top]
    set footer [string trimright [three_parts $bottom]]
    set lineno 1
    set pageno 1
    set blankP 0
    set eatP 0

    if {$passno == 2} {
        set indexpg 0
    }

    for {set i 0} {$i < 4} {incr i} {
        write_line_txt "" -1
    }
    set left [munge_long $left]
    set right [munge_long $right]
    foreach l $left r $right {
        set l [chars_expand $l]
        set r [chars_expand $r]
        set len [expr 72-[string length $l]]
        write_line_txt [format %s%*.*s $l $len $len $r]
    }
    write_line_txt "" -1
    write_line_txt "" -1

    foreach line $title {
        write_text_txt [chars_expand $line] c
    }

    write_line_txt "" -1

    if {!$options(.PRIVATE)} {
        write_line_txt "Status of this Memo"
        foreach para $status {
            write_line_txt ""
            pcdata_txt $para
        }
    }

    if {(!$options(.PRIVATE)) && $copyrightP} {
        write_line_txt "" -1
        write_line_txt "Copyright Notice"
        write_line_txt "" -1
        pcdata_txt $copying
    }
    incr lineno -1
}

proc three_parts {stuff} {
    set result [chars_expand [lindex $stuff 0]]
    set len [string length $result]

    set text [chars_expand [lindex $stuff 1]]
    set len [expr (73-[string length $text])/2-$len]
    if {$len < 4} {
        set len 4
    }
    append result [format %*.*s%s $len $len "" $text]
    set len [string length [set text [chars_expand [lindex $stuff 2]]]]
    set len [expr (72-[string length $result])-$len]
    append result [format %*.*s%s $len $len "" $text]

    return $result
}

proc front_txt_end {toc irefP} {
    global options
    global header footer lineno pageno blankP
    global indexpg

    if {$options(.TOC)} {
        set last [lindex $toc end]
        if {[string compare [lindex $last 1] "Full Copyright Statement"]} {
            set last ""
        } else {
            set toc [lreplace $toc end end]
        }
        if {$irefP} {
            lappend toc [list "" Index $indexpg]
        }
        if {[string compare $last ""]} {
            lappend toc $last
        }

        if {(![have_lines [expr [llength $toc]+3]]) || ($lineno > 17)} {
            end_page_txt
        } else {
            write_line_txt "" -1
        }
        write_line_txt "Table of Contents"
        write_line_txt "" -1

        set len1 0
        set len2 0
        foreach c $toc {
            if {[set x [string length [lindex $c 0]]] > $len1} {
                set len1 $x
            }
            if {[set x [string length [lindex $c 2]]] > $len2} {
                set len2 $x
            }
        }
        set mid [expr 72-($len1+$len2+5)]

        foreach c $toc {
            if {!$options(.TOCOMPACT)} {
                if {[string last . [lindex $c 0]] \
                        == [expr [string length [lindex $c 0]]-1]} {
                    write_line_txt ""
                }
            }
            set s1 [format "   %-*.*s " $len1 $len1 [lindex $c 0]]
            set s2 [format " %*.*s" $len2 $len2 [lindex $c 2]]
            set title [chars_expand [string trim [lindex $c 1]]]
            while {[set i [string length $title]] > $mid} {
                set phrase [string range $title 0 [expr $mid-1]]
                if {[set x [string last " " $phrase]] < 0} {
                    if {[set x [string first " " $title]] < 0} {
                        break
                    }
                }
                write_toc_txt $s1 [string range $title 0 [expr $x-1]] \
                        [format " %-*.*s" $len2 $len2 ""] $mid 0
                set s1 [format "   %-*.*s " $len1 $len1 ""]
                set title [string trimleft [string range $title $x end]]
            }
            write_toc_txt $s1 $title $s2 $mid 1
        }
    }

    if {($options(.TOC) || !$options(.COMPACT))} {
        end_page_txt
    }
}

proc write_toc_txt {s1 title s2 len dot} {
    set x [string length $title]
    if {($dot) && ($x < $len)} {
        if {$x%2} {
            append title " "
            incr x
        }
        while {$x < $len} {
            append title " ."
            incr x 2
        }
    }

    write_line_txt [format "%s%-*.*s%s" $s1 $len $len $title $s2]
}

proc abstract_txt {} {
    write_line_txt "" -1
    write_line_txt "Abstract"
    write_line_txt "" -1
}

proc note_txt {title depth} {
    write_line_txt "" -1
    write_line_txt [chars_expand $title]
    write_line_txt "" -1
}

proc section_txt {prefix top title lines anchor} {
    global options
    global header footer lineno pageno blankP

    if {($top && !$options(.COMPACT)) || (![have_lines [expr $lines+5]])} {
        end_page_txt
    } else {
        write_line_txt "" -1
    }

    push_indent -3
    write_text_txt "$prefix "
    push_indent [expr [string length $prefix]+1]
    write_text_txt [chars_expand $title]
    flush_text
    pop_indent
    pop_indent

    return $pageno
}

proc t_txt {tag counter style hangText editNo} {
    global options
    global eatP

    if {![string compare $tag end]} {
        return
    }

    if {[string compare $counter ""]} {
        set pos [pop_indent]
        set l [split $counter .]
        switch -- $style {
            numbers {
                set counter "[lindex $l end]. "
            }

            symbols {
                set counter "[lindex { - o * + } [expr [llength $l]%4]] "
            }

            hanging {
                set counter "$hangText "
            }

            default {
                set counter "  "
            }
        }
        flush_text
        if {$options(.EDITING)} {
            write_editno_txt $editNo
        } elseif {!$options(.SUBCOMPACT)} {
            write_line_txt ""
        }
        write_text_txt [format "%0s%-[expr $pos-0]s" "" $counter]
        push_indent $pos
    } else {
        if {$options(.EDITING)} {
            write_editno_txt $editNo
        } else {
            write_line_txt ""
        }
    }

    set eatP 1
}

proc list_txt {tag counters style hangIndent hangText} {
    global options
    global eatP

    switch -- $tag {
        begin {
            switch -- $style {
                numbers {
                    set i 0
                    foreach counter $counters {
                        if {[set j [string length \
                                           [lindex [split $counter .] end]]] \
                                > $i} {
                            set i $j
                        }
                    }
                    incr i 1
                }

                format {
                    set i [expr [string length $hangText]-1]
                }

                default {
                    set i 1
                }
            }
            if {[incr i 2] > $hangIndent} {
                push_indent [expr $i+0]
            } else {
                push_indent [expr $hangIndent+0]
            }
        }

        end {
            flush_text
            if {!$options(.SUBCOMPACT)} {
                write_line_txt ""
            }
            pop_indent

            set eatP 1
        }
    }
}

proc figure_txt {tag lines anchor src title} {
    global counter depth elemN elem passno stack xref

    switch -- $tag {
        begin {
            if {[string compare $title ""]} {
                incr lines 8
            }
            if {![have_lines $lines]} {
                end_page_txt
            }
            if {[string compare $title ""]} {
                write_line_txt ""
                write_line_txt \
                    "   ---------------------------------------------------------------------"
                write_line_txt ""
            }
        }

        end {
            if {[string compare $title ""]} {
                if {[string compare $anchor ""]} {
                    array set av $xref($anchor)
                    set prefix "Figure $av(value): "
                } else {
                    set prefix ""
                }
                write_line_txt ""
                write_text_txt "$prefix$title" c
                write_line_txt ""
                write_line_txt \
                    "   ---------------------------------------------------------------------"
                write_line_txt ""
            }
        }
    }
}

proc preamble_txt {tag {editNo ""}} {
    global options

    switch -- $tag {
        begin {
            if {$options(.EDITING)} {
                write_editno_txt $editNo
            } else {
                write_line_txt ""
            }
        }
    }
}

proc postamble_txt {tag {editNo ""}} {
    global options
    global eatP

    switch -- $tag {
        begin {
            set eatP 1
            if {$options(.EDITING)} {
                write_editno_txt $editNo
            }
        }
    }
}

proc xref_txt {text av target} {
    global eatP

    array set attrs $av    

    switch -- $attrs(type) {
        section {
            set line "Section $attrs(value)"
        }

        appendix {
            set line "Appendix $attrs(value)"
        }

        figure {
            set line "Figure $attrs(value)"
        }

        default {
            set line "\[$attrs(value)\]"
        }
    }
    if {[string compare $text ""]} {
        switch -- $attrs(type) {
            section
                -
            appendix
                -
            figure {
                set line "[chars_expand $text] ($line)"
            }

            default {
                set line "[chars_expand $text] $line"
            }
        }       
    }
    write_text_txt $line

    set eatP 0
}

proc eref_txt {text counter target} {
    global eatP
    global erefs

    if {[string compare $text ""]} {
        set line "[chars_expand $text]"
    }
    if {([string first "#" $target] < 0) \
            && ([string compare $text $target])} {
        set erefs($counter) $target
        append line " \[$counter\]"
    }
    write_text_txt $line

    set eatP 0
}

proc iref_txt {item subitem} {
    global header footer lineno pageno blankP

    return $pageno
}

proc vspace_txt {lines} {
    global header footer lineno pageno blankP
    global eatP

    flush_text
    if {$lineno+$lines >= 51} {
        end_page_txt
    } else {
        while {$lines > 0} {
            incr lines -1

            write_it ""
            incr lineno
        }
    }

    set eatP 1
}

proc references_txt {tag {title ""} {erefP 0}} {
    global counter depth elemN elem passno stack xref
    global options
    global header footer lineno pageno blankP

    switch -- $tag {
        begin {
            if {$options(.COMPACT)} {
                write_line_txt ""
            } else {
                end_page_txt
            }
            write_line_txt $title

            return $pageno
        }

        end {
            if {$erefP} {
                erefs_txt
            } else {
                flush_text
            }
        }
    }
}

proc erefs_txt {{title ""}} {
    global erefs
    global options

    if {[string compare $title ""]} {
        if {$options(.COMPACT)} {
            write_line_txt ""
        } else {
            end_page_txt
        }
        write_line_txt $title
    }

    set names  [lsort -integer [array names erefs]]
    set width [expr [string length [lindex $names end]]+2]
    foreach eref $names {
        write_line_txt ""

        set i [expr [string length \
                            [set prefix \
                                 [format %-*.*s $width $width \
                                         "\[$eref\]"]]+2]]
        write_text_txt $prefix

        push_indent $i

        write_text_txt "  "
        write_url $erefs($eref)

        pop_indent
    }

    flush_text
}

proc reference_txt {prefix names title series date anchor target target2
                    width} {
    write_line_txt ""

    incr width 2
    set i [expr [string length \
                        [set prefix \
                             [format %-*.*s $width $width "\[$prefix\]"]]+2]]
    write_text_txt $prefix

    push_indent $i

    set hack $names
    set names ""
    foreach name $hack {
        if {[string compare [lindex $name 0] ""]} {     
            lappend names $name
        }
    }
    set nameN [llength $names]

    set s "  "
    set nameA 1
    foreach name $names {
        incr nameA
        write_text_txt $s[chars_expand [lindex $name 0]]
        if {$nameA == $nameN} {
            set s " and "
        } else {
            set s ", "
        }
    }
    write_text_txt "$s\"[chars_expand $title]\""
    foreach serial $series {
        if {[regexp -nocase -- "internet-draft (draft-.*)" $serial x n] == 1} {
            set serial "$n (work in progress)"
        }
        write_text_txt ", [chars_expand $serial]"
    }
    if {[string compare $date ""]} {
        write_text_txt ", $date"
    }
    if {[string compare $target ""]} {
        write_text_txt ", "
        write_url $target
    }
    write_text_txt .

    pop_indent
}

proc back_txt {authors} {
    global options
    global header footer lineno pageno blankP
    global contacts

    set lines 5
    set author [lindex $authors 0]
    incr lines [llength [lindex $author 0]]
    incr lines [llength [lindex $author 1]]
    if {![have_lines $lines]} {
        end_page_txt
    } elseif {$lineno != 3} {
        write_line_txt "" -1
        write_line_txt "" -1
    }
    set result $pageno

    switch -- [llength $authors] {
        0 {
            return $result
        }

        1 {
            set s1 "'s"
            set s2 ""
        }

        default {
            set s1 "s'"
            set s2 "es"
        }
    }
    set s "Author$s1 Address$s2"

    set firstP 1
    foreach author $authors {
        set block1 [lindex $author 0]
        set block2 [lindex $author 1]

        set lines 3
        incr lines [llength $block1]
        incr lines [llength $block2]
        if {![have_lines $lines]} {
            end_page_txt
        }

        if {[string compare $s ""]} {
            write_line_txt $s
            set s ""
        } else {
            write_line_txt "" -1
        }
        write_line_txt "" -1

        foreach line $block1 {
            write_line_txt "   [chars_expand $line]"
        }

        if {[llength $block2] > 0} {
            write_line_txt ""
            foreach contact $block2 {
                set key [lindex $contact 0]
                set value [lindex [lindex $contacts \
                                          [lsearch0 $contacts $key]] 1]
                set value [format %-6s $value:]
                write_line_txt "   $value [chars_expand [lindex $contact 1]]"
            }
        }
    }

    return $result
}

proc pcdata_txt {text {pre 0}} {
    global eatP
    global options

    if {(!$pre) && ($eatP)} {
        set text [string trimleft $text]
    }
    set eatP 0

    if {!$pre} {
        regsub -all "\n\[ \t\n\]*" $text "\n" text
        regsub -all "\[ \t\]*\n\[ \t\]*" $text "\n" text
        set prefix ""

        if {$options(.EMOTICONIC)} {
            set text [emoticonic_txt $text]
        }
    }

    foreach line [split $text "\n"] {
        set line [chars_expand $line]
        if {$pre} {
            write_line_txt [string trimright $line] 1
        } else {
            write_pcdata_txt $prefix$line
            set prefix " "
        }
    }
}

proc emoticonic_txt {text} {
    foreach {ei begin end} [list  *   *   * \
                                  '   '   ' \
                                 {"} {"} {"}] {
        set body ""
        while {[set x [string first "|$ei" $text]] >= 0} {
            if {$x > 0} {
                append body [string range $text 0 [expr $x-1]]
            }
            append body "$begin"
            set text [string range $text [expr $x+2] end]
            if {[set x [string first "|" $text]] < 0} {
                error "missing close for |$ei"
            }
            if {$x > 0} {
                set inline [string range $text 0 [expr $x-1]]
                if {[string first $begin $inline] == 0} {
                    set inline [string range $inline [string length $begin] \
                                       end]
                }
                set tail [expr [string length $inline]-[string length $end]]
                if {[string last $end $inline] == $tail} {
                    set inline [string range $inline 0 [expr $tail-1]]
                }

                append body $inline
            }
            append body "$end"
            set text [string range $text [expr $x+1] end]
        }
        append body $text
        set text $body
    }

    return $text
}

proc start_page_txt {} {
    global stdout
    global header footer lineno pageno blankP

    write_it $header
    write_it ""
    write_it ""
    set lineno 3
    set blankP 1
}

proc end_page_txt {} {
    global stdout
    global header footer lineno pageno blankP

    flush_text

    if {$lineno <= 3} {
        return
    }
    while {$lineno < 54} {
        write_it ""
        incr lineno
    }

    set text [format "\[Page %d\]" $pageno]
    incr pageno
    set len [string length $text]
    set len [expr (72-[string length $footer])-$len]
    if {$len < 4} {
        set len 4
    }
    write_it [format %s%*.*s%s $footer $len $len "" $text]
    write_it "\f"

    set lineno 0
}

proc write_pcdata_txt {text} {
    global buffer
    global indents indent

    if {![string compare $buffer ""]} {
        set buffer [format %*.*s $indent $indent ""]    
    }
    append buffer $text
    set buffer [two_spaces $buffer]

    write_text_txt ""
}

proc write_editno_txt {editNo} {
    global buffer
    global indents indent

    if {[string compare $buffer ""]} {
        flush_text
    }
    set buffer <$editNo>
    flush_text
}

proc write_text_txt {text {direction l}} {
    global buffer
    global indents indent

    if {![string compare $buffer ""]} {
        set buffer [format %*.*s $indent $indent ""]    
    }
    append buffer $text

    set flush [string compare $direction l]
    while {([set i [string length $buffer]] > 72) || ($flush)} {
        if {$i > 72} {
            set x [string last " " [set line [string range $buffer 0 72]]]
            set y [string last "-" [string range $line 0 71]]
            set z [string last "/" [string range $line 0 71]]
            if {$y < $z} {
                set y $z
            }
            if {$x < $y} {
                set x $y
            }
            if {$x < 0} {
                set x [string last " " $buffer]
                set y [string last "-" $buffer]
                set z [string last "/" $buffer]
                if {$y > $z} {
                    set y $z
                }
                if {$x > $y} {
                    set x $y
                }
            }
            if {$x < 0} {
                set x $i
            } elseif {($x == $y) || ($x == $z)} {
                incr x
            } elseif {$x+1 == $indent} {
                set x $i
            }
            set text [string range $buffer 0 [expr $x-1]]
            set rest [string trimleft [string range $buffer $x end]]
        } else {
            set text $buffer
            set rest ""
        }
        set buffer ""

        if {![string compare $direction c]} {
            set text [string trimleft $text]
            set len [expr (72-[string length $text])/2]
            set text [format %*.*s%s $len $len "" $text]
        }
        write_line_txt $text

        if {[string compare $rest ""]} {
            set buffer [format %*.*s%s $indent $indent "" $rest]
        } else {
            break
        }
    }
}

proc write_line_txt {line {pre 0}} {
    global stdout
    global header footer lineno pageno blankP
    global buffer
    global nbsp

    flush_text
    if {$lineno == 0} {
        start_page_txt
    }
    if {![set x [string compare $line ""]]} {
        set blankO $blankP
        set blankP 1
        if {($blankO) && (!$pre || $lineno == 3)} {
            return
        }
    } else {
        set blankP 0
    }
    if {($pre) && ($x)} {
        set pre "   "
    } else {
        set pre ""
    }
    regsub -all "$nbsp" $line " " line
    write_it [string trimright $pre$line]
    incr lineno
    if {$lineno >= 51} {
        end_page_txt
    }
}

proc two_spaces {glop} {
    set post ""

    while {[string length $glop] > 0} {
        if {[set x [string first ". " $glop]] < 0} {
            append post $glop
            break
        }

        append post [string range $glop 0 [expr $x+1]]
        set glop [string range $glop [expr $x+2] end]
        if {[string first " " $glop] != 0} {
            append post " "
        }
    }

    return $post
}

#
# html output
#


# don't need to return anything even though rfc_txt does...

proc rfc_html {irefs copying} {
    global options copyrightP
    global funding
    global stdout

    if {$options(.SLIDES) && [end_rfc_slides]} {
        return
    }

    if {[llength $irefs] > 0} {
        toc_html rfc.index
        puts $stdout "<h3>Index</h3>"

        puts $stdout "<table>"
        foreach iref $irefs {
            foreach {L item subitem pages} $iref { break }

            if {[string compare $L ""]} {
                puts $stdout "<tr><td><b>$L</b></td><td>&nbsp;</td></tr>"
            }
            
            if {[string compare $subitem ""]} {
                if {[string compare $item ""]} {
                    puts $stdout "<tr><td>&nbsp;</td><td>$item</td></tr>"
                }
                set key $subitem
                set t "&nbsp;&nbsp;"
            } else {
                set key $item
                set t ""
            }

            if {[llength $pages] == 1} {
                set key "<a href=\"#[lindex $pages 0]\">$key</a>"
            } else {
                set i 0
                set s "  "
                foreach page $pages {
                    append key "$s<a href=\"#$page\">[incr i]</a>"
                    set s ", "
                }
            }

            puts $stdout "<tr><td>&nbsp;</td><td>$t$key</td></tr>"
        }
        puts $stdout "</table>"
    }

    if {(!$options(.PRIVATE)) && $copyrightP} {
        toc_html rfc.copyright
        puts $stdout "<h3>Full Copyright Statement</h3>"

        foreach para $copying {
            puts $stdout "<p class='copyright'>"
            pcdata_html $para
            puts $stdout "</p>"
        }

        puts $stdout "<h3>Acknowledgement</h3>"
        puts $stdout "<p class='copyright'>"
        pcdata_html $funding
        puts $stdout "</p>"
    }

    puts $stdout "</font></body></html>"

    return ""
}

global htmlstyle

set htmlstyle \
"<STYLE type='text/css'>
    .title { color: #990000; font-size: 22px; line-height: 22px; font-weight: bold; text-align: right;
             font-family: helvetica, arial, sans-serif }
    .filename { color: #666666; font-size: 18px; line-height: 28px; font-weight: bold; text-align: right;
                  font-family: helvetica, arial, sans-serif }
    p.copyright { color: #000000; font-size: 10px;
                  font-family: verdana, charcoal, helvetica, arial, sans-serif }
    p { margin-left: 2em; margin-right: 2em; }
    li { margin-left: 3em;  }
    ol { margin-left: 2em; margin-right: 2em; }
    ul.text { margin-left: 2em; margin-right: 2em; }
    pre { margin-left: 3em; color: #333333 }
    ul.toc { color: #000000; line-height: 16px;
             font-family: verdana, charcoal, helvetica, arial, sans-serif }
    H3 { color: #333333; font-size: 16px; line-height: 16px; font-family: helvetica, arial, sans-serif }
    H4 { color: #000000; font-size: 14px; font-family: helvetica, arial, sans-serif }
    TD.header { color: #ffffff; font-size: 10px; font-family: arial, helvetica, san-serif; valign: top }
    TD.author-text { color: #000000; font-size: 10px;
                     font-family: verdana, charcoal, helvetica, arial, sans-serif }
    TD.author { color: #000000; font-weight: bold; margin-left: 4em; font-size: 10px; font-family: verdana, charcoal, helvetica, arial, sans-serif }
    A:link { color: #990000; font-size: 10px; text-transform: uppercase; font-weight: bold;
             font-family: MS Sans Serif, verdana, charcoal, helvetica, arial, sans-serif }
    A:visited { color: #333333; font-weight: bold; font-size: 10px; text-transform: uppercase;
                font-family: MS Sans Serif, verdana, charcoal, helvetica, arial, sans-serif }
    A:name { color: #333333; font-weight: bold; font-size: 10px; text-transform: uppercase;
             font-family: MS Sans Serif, verdana, charcoal, helvetica, arial, sans-serif }
    .link2 { color:#ffffff; font-weight: bold; text-decoration: none;
             font-family: monaco, charcoal, geneva, MS Sans Serif, helvetica, monotype, verdana, sans-serif;
             font-size: 9px }
    .RFC { color:#666666; font-weight: bold; text-decoration: none;
           font-family: monaco, charcoal, geneva, MS Sans Serif, helvetica, monotype, verdana, sans-serif;
           font-size: 9px }
    .hotText { color:#ffffff; font-weight: normal; text-decoration: none;
               font-family: charcoal, monaco, geneva, MS Sans Serif, helvetica, monotype, verdana, sans-serif;
               font-size: 9px }
</style>"


proc front_html_begin {left right top bottom title status copying} {
    global options copyrightP
    global stdout
    global htmlstyle
    global hangP

    set hangP 0

    if {$options(.SLIDES) \
            && [front_slides_begin $left $right $top $bottom $title]} {
        return
    }

    puts -nonewline $stdout "<html><head><title>"
    if {($options(.PRIVATE)) \
            && ([string compare [string trim $options(private)] ""])} {
        pcdata_html "$options(private): "
    }
    pcdata_html [lindex $title 0]
    puts $stdout "</title>"
    if {$options(.PRIVATE)} {
        puts -nonewline $stdout "<meta http-equiv=\"Expires\" content=\""
        puts -nonewline $stdout [clock format [clock seconds] \
                                      -format "%a, %d %b %Y %T +0000" \
                                      -gmt true]
        puts $stdout "\">"
    }
    puts $stdout "$htmlstyle\n</head>"
    puts -nonewline $stdout "<body bgcolor=\"#ffffff\""
    if {[string compare $options(background) ""]} {
        puts -nonewline $stdout " background=\"$options(background)\""
    }
    puts $stdout " text=\"#000000\" alink=\"#000000\" vlink=\"#666666\" link=\"#990000\">" 

    xxxx_html

    puts $stdout "<table width=\"66%\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\"><tr><td><table width=\"100%\" border=\"0\" cellpadding=\"2\" cellspacing=\"1\">"
    set left [munge_long $left]
    set right [munge_long $right]
    set lc ""
    set rc ""
    foreach l $left r $right {
        if {[string compare $l ""]} {
            set l $l
        } else {
            set l "&nbsp;"
        }
        if {[string compare $r ""]} {
            set r $r
        } else {
            set r "&nbsp;"
        }
        puts $stdout "<tr valign=\"top\"><td width=\"33%\" bgcolor=\"#666666\" class=\"header\">$l</td><td width=\"33%\" bgcolor=\"#666666\" class=\"header\">$r</td></tr>"
    }
    puts $stdout "</table></td></tr></table>"

    set color 990000
    set size 3
    set br <br>
    set class title
    foreach line $title {
        puts -nonewline $stdout "<div align=\"right\"><font face=\"monaco, MS Sans Serif\" color=\"#$color\" size=\"+$size\"><b>$br<span class=\"$class\">"
        pcdata_html $line
        puts $stdout "</span></b></font></div>"
        set color 666666
        set size 2
        set br ""
        set class filename
    }
    puts $stdout "<font face=\"verdana, helvetica, arial, sans-serif\" size=\"2\">"

    if {!$options(.PRIVATE)} {
        puts $stdout ""
        puts $stdout "<h3>Status of this Memo</h3>"
        foreach para $status {
            puts $stdout "<p>"
            pcdata_html $para
            puts $stdout "</p>"
        }
    }

    if {(!$options(.PRIVATE)) && $copyrightP} { 
        puts $stdout ""
        puts $stdout "<h3>Copyright Notice</h3>"
        puts $stdout "<p>"
        pcdata_html $copying
        puts $stdout "</p>"
    }
}

proc front_html_end {toc irefP} {
    global options copyrightP
    global stdout
    global passno indexpg

    if {(!$options(.TOC)) || ($passno > 2)} {
        return
    }

    xxxx_html toc

    puts $stdout "<h3>Table of Contents</h3>"
    puts $stdout "<ul compact class=\"toc\">"
    set last [lindex $toc end]
    if {[string compare [lindex $last 1] "Full Copyright Statement"]} {
        set last ""
    } else {
        set toc [lreplace $toc end end]
    }
    if {$irefP} {
        lappend toc [list "&#167;" Index rfc.index]
    }
    if {[string compare $last ""]} {
        lappend toc $last
    }
    foreach c $toc {
        puts -nonewline $stdout "<b><a href=\"#[lindex $c 2]\">"
        pcdata_html [lindex $c 0]
        puts $stdout "</a>&nbsp;"
        pcdata_html [lindex $c 1]
        puts $stdout "<br></b>"
    }
    puts $stdout "</ul>"
    puts $stdout "<br clear=\"all\">"
}

proc abstract_html {} {
    global options
    global stdout

    if {$options(.SLIDES) && [end_page_slides]} {
        start_page_slides Abstract
    } else {
        puts $stdout ""
        puts $stdout "<h3>Abstract</h3>"
    }
}

proc note_html {title depth} {
    global options
    global stdout

    if {$options(.SLIDES) && [end_page_slides]} {
        start_page_slides $title
    } else {
        incr depth 3

        puts $stdout ""
        puts -nonewline $stdout "<h$depth>"
        pcdata_html $title
        puts $stdout "</h$depth>"
    }
}

proc section_html {prefix top title {lines 0} anchor} {
    global options
    global stdout

    if {$options(.SLIDES) && [end_page_slides]} {
        start_page_slides $title

        return $anchor
    }

    puts $stdout ""
    if {[string match *. $prefix]} {
        toc_html $anchor
        puts -nonewline $stdout "<h3>$prefix&nbsp;"
        pcdata_html $title
        puts $stdout "</h3>"
    } else {
        puts -nonewline $stdout "<h4><a name=\"$anchor\">$prefix</a>&nbsp;"
        pcdata_html $title
        puts $stdout "</h4>"
    }

    return $anchor
}

proc t_html {tag counter style hangText editNo} {
    global options
    global stdout
    global hangP

    if {[string compare $tag begin]} {
        set s /
    } else {
        set s ""
    }
    puts $stdout ""
    if {![string compare $style "hanging"]} {
        if {![string compare $tag begin]} {
            puts $stdout "<dt>$hangText</dt>"
        }
        puts $stdout "<${s}dd>"

        set hangP 1
    } elseif {([string compare $counter ""]) \
                    && ([string compare $style empty])} {
        puts $stdout "<${s}li>"

        set hangP 0
    } else {
        puts $stdout "<${s}p>"

        set hangP 0
    }
    if {$options(.EDITING) \
            && (![string compare $tag begin]) \
            && ([string compare $editNo ""])} {
        puts $stdout "<sup><small>$editNo</small></sup>"
    }
}

proc list_html {tag counters style hangIndent hangText} {
    global stdout
    global hangP

    if {[string compare $tag begin]} {
        set s /
        set c ""
    } else {
        set s ""
        set c " class=\"text\""
    }
    puts $stdout ""
    switch -- $style {
        numbers {
            puts $stdout "<${s}ol$c>"
        }

        symbols {
            puts $stdout "<${s}ul$c>"
        }

        hanging {
            if {[string compare $tag begin]} {
                puts $stdout "</dl></blockquote>"
            } else {
                puts $stdout "<blockquote$c><dl>"
            }
        }

        default {
            puts $stdout "<${s}blockquote$c>"
        }
    }

    if {[string compare $tag begin]} {
        puts $stdout "<p>"
    }

    set hangP 0
}

proc figure_html {tag lines anchor src title} {
    global options
    global stdout

    switch -- $tag {
        begin {
            if {[string compare $title ""]} {
                puts $stdout "<br><hr size=\"1\" shade=\"0\">"
            }
            if {[string compare $anchor ""]} {
                puts $stdout "<a name=\"$anchor\"></a>"
            }
            if {$options(.SLIDES) && ([string compare $src ""])} {
                puts $stdout "<img src=\"$src\"></img>"
            }
        }

        end {
            if {[string compare $title ""]} {
                puts $stdout "<table border=\"0\" cellpadding=\"0\" cellspacing=\"2\" align=\"center\"><tr><td align=\"center\"><font face=\"monaco, MS Sans Serif\" size=\"1\"><b>&nbsp;$title&nbsp;</b></font><br></td></tr></table><hr size=\"1\" shade=\"0\">"
            }
        }
    }
}

proc preamble_html {tag {editNo ""}} {
    t_html $tag "" "" "" $editNo
}

proc postamble_html {tag {editNo ""}} {
    t_html $tag "" "" "" $editNo
}

proc xref_html {text av target} {
    global elem
    global options
    global stdout

    array set attrs $av    

    set elemY $attrs(elemN)
    array set tv [list title ""]
    array set tv $elem($elemY)

    switch -- $attrs(type) {
        section {
            set line "Section $attrs(value)"
        }

        appendix {
            set line "Appendix $attrs(value)"
        }

        figure {
            set line "Figure $attrs(value)"
        }

        default {
            set line "\[$attrs(value)\]"
        }
    }

    if {![string compare $text ""]} {
        set text $tv(title)
    } elseif {$options(.EMOTICONIC)} {
        set text [emoticonic_html $text]
    }

    set post ""
    if {[string compare $text ""]} {
        switch -- $attrs(type) {
            section
                -
            appendix
                -
            figure {
            }

            default {
                set post $line
            }
        }
    } else {
        set text $line
    }

    puts -nonewline $stdout "<a href=\"#$target\">$text</a>$post"
}

proc eref_html {text counter target} {
    global options
    global stdout

    if {![string compare $text ""]} {
        set text $target
    } elseif {$options(.EMOTICONIC)} {
        set text [emoticonic_html $text]
    } 

    puts -nonewline $stdout "<a href=\"$target\">$text</a>"
}

proc iref_html {item subitem} {
    global anchorN
    global stdout

    set anchor anchor[incr anchorN]

    puts -nonewline $stdout "<a name=\"$anchor\"></a>"

    return $anchor
}

proc vspace_html {lines} {
    global options
    global stdout
    global hangP

    if {$lines > 5} {
        if {$options(.SLIDES) && [end_page_slides]} {
            start_page_slides
        }

        return
    }
    incr lines -$hangP
    while {$lines >= 0} {
        incr lines -1
        puts $stdout "<br>"
    }

    set hangP 0
}

# don't need to return anything even though txt/nr versions do...

proc references_html {tag {title ""} {erefP 0}} {
    global counter depth elemN elem passno stack xref
    global options
    global stdout

    if {$options(.SLIDES) \
            && (![string compare $tag begin]) \
            && [end_page_slides]} {
        [start_page_slides Abstract]
        return
    }

    switch -- $tag {
        begin {
            if {![info exists counter(references)]} {
                set counter(references) 0
            }

            puts $stdout ""
            toc_html rfc.references[incr counter(references)]
            puts -nonewline $stdout "<h3>"
            pcdata_html $title
            puts $stdout "</h3>"

            puts $stdout "<table width=\"99%\" border=\"0\">"
        }

        end {
            puts $stdout "</table>"
        }
    }
}

proc reference_html {prefix names title series date anchor target target2
                     width} {
    global rfcTxtHome idTxtHome
    global rfcHtmlHome
    global stdout

    if {[string compare $target2 ""]} {
        set prefix "<a href=\"$target2\">$prefix</a>"
    }
    if {[string compare $anchor ""]} {
        set prefix "<a name=\"$anchor\">\[$prefix\]</a>"
    }
    puts $stdout "<tr><td class=\"author-text\" valign=\"top\"><b>$prefix</b></td>"

    set hack $names
    set names ""
    foreach name $hack {
        if {[string compare [lindex $name 0] ""]} {     
            lappend names $name
        }
    }
    set nameN [llength $names]

    set s ""
    set text ""
    set nameA 1
    foreach name $names {
        incr nameA
        if {[string compare [set eref [lindex $name 1]] ""]} {
            set name "<a href=\"$eref\">[lindex $name 0]</a>"
        } else {
            set name [lindex $name 0]
        }
        append text $s$name
        if {$nameA == $nameN} {
            set s " and "
        } else {
            set s ", "
        }
    }

    if {![string compare $target ""]} {
        foreach serial $series {
            if {[regexp -nocase -- "rfc (\[0-9\]*)" $serial x n] == 1} {
                if {[catch { set rfcHtmlHome }]} {
                    set target $rfcTxtHome/rfc$n.txt
                } else {
                    set target $rfcHtmlHome/rfc$n.html
                }
                break
            }
            if {[regexp -nocase -- "internet-draft (draft-.*)" $serial x n] \
                    == 1} {
                set target $idTxtHome/$n.txt
                break
            }
        }
    }
    if {[string compare $target ""]} {
        set title "<a href=\"$target\">$title</a>"
    }
    append text "$s\"$title\""
    foreach serial $series {
        if {[regexp -nocase -- "internet-draft (draft-.*)" $serial x n] == 1} {
            set serial "$n (work in progress)"
        }
        append text ", $serial"
    }
    if {[string compare $date ""]} {
        append text ", $date"
    }
    append text .
    puts -nonewline $stdout "<td class=\"author-text\">"
    pcdata_html $text
    puts $stdout "</td></tr>"
}

# don't need to return anything even though back_txt does...

proc back_html {authors} {
    global stdout
    global contacts

    switch -- [llength $authors] {
        0 {
            return
        }

        1 {
            set s1 "'s"
            set s2 ""
        }

        default {
            set s1 "s'"
            set s2 "es"
        }
    }
    puts $stdout ""

    toc_html rfc.authors
    puts $stdout "<h3>Author$s1 Address$s2</h3>"

    puts $stdout \
         "<table width=\"99%\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\">"
    set s ""
    foreach author $authors {
        set block1 [lindex $author 0]
        set block2 [lindex $author 1]

        if {[string compare $s ""]} {
            puts $stdout $s
        }
        foreach line $block1 {
            puts $stdout "<tr><td class=\"author-text\">&nbsp;</td>"
            puts $stdout "<td class=\"author-text\">$line</td></tr>"
        }
        foreach contact $block2 {
            set key [lindex $contact 0]
            set value [lindex [lindex $contacts \
                                      [lsearch0 $contacts $key]] 1]
            puts $stdout "<tr><td class=\"author\" align=\"right\">$value:&nbsp;</td>"
            set value [lindex $contact 1]
            switch -- $key {
                email {
                    set value "<a href=\"mailto:$value\">$value</a>"
                }

                uri {
                    set value "<a href=\"$value\">$value</a>"
                }
            }
            puts $stdout "<td class=\"author-text\">$value</td></tr>"
        }
        set s "<tr cellpadding=\"3\"><td>&nbsp;</td><td>&nbsp;</td></tr>"
    }
    puts $stdout "</table>"

    return ""
}

proc xxxx_html {{anchor {}}} {
    global elem
    global options
    global stdout

    if {$options(.PRIVATE)} {
        toc_html $anchor
        return
    } else {
        array set rv $elem(1)
        if {![string compare [set number $rv(number)] ""]} {
            toc_html $anchor
            return
        }
    }                               

    if {[string compare $anchor ""]} {
        puts $stdout "<a name=\"$anchor\"><hr size=\"1\" shade=\"0\"></a>"
    }

    puts $stdout "
<table border=\"0\" cellpadding=\"0\" cellspacing=\"2\" width=\"30\" height=\"30\" align=\"right\">
    <tr>
        <td bgcolor=\"#000000\" align=\"center\" valign=\"center\" width=\"30\" height=\"30\">
            <font face=\"monaco, MS Sans Serif\" color=\"#666666\" size=\"1\">
                <b><span class=\"RFC\">&nbsp;RFC&nbsp;</span></b>
            </font>
            <font face=\"charcoal, MS Sans Serif, helvetica, arial, sans-serif\" size=\"1\" color=\"#ffffff\">
                <span class=\"hotText\">$number</span>
            </font>
        </td>
    </tr>"

    if {$options(.TOC)} {
        puts $stdout "    <tr><td bgcolor=\"#990000\" align=\"center\" width=\"30\" height=\"15\"><a href=\"#toc\" CLASS=\"link2\"><font face=\"monaco, MS Sans Serif\" color=\"#ffffff\" size=\"1\"><b>&nbsp;TOC&nbsp;</b></font></a><br></td></tr>"
    }
    puts $stdout "</table>"
}

proc toc_html {anchor} {
    global options
    global stdout

    if {[string compare $anchor ""]} {
        puts $stdout "<a name=\"$anchor\"><br><hr size=\"1\" shade=\"0\"></a>"
    }

    if {!$options(.TOC)} {
        return
    }

    puts $stdout "<table border=\"0\" cellpadding=\"0\" cellspacing=\"2\" width=\"30\" height=\"15\" align=\"right\"><tr><td bgcolor=\"#990000\" align=\"center\" width=\"30\" height=\"15\"><a href=\"#toc\" CLASS=\"link2\"><font face=\"monaco, MS Sans Serif\" color=\"#ffffff\" size=\"1\"><b>&nbsp;TOC&nbsp;</b></font></a><br></td></tr></table>"
}

proc pcdata_html {text {pre 0}} {
    global entities
    global options
    global stdout

    set font "<font face=\"verdana, helvetica, arial, sans-serif\" size=\"2\">"

    regsub -all -nocase {&apos;} $text {\&#039;} text
    regsub -all "&rfc.number;" $text [lindex $entities 1] text
    if {$pre} {
        if {![slide_pre $text]} {
            puts $stdout "</font><pre>$text</pre>$font"
        }
    } else {
        if {$options(.EMOTICONIC)} {
            set text [emoticonic_html $text]
        }

        puts -nonewline $stdout $text
    }
}

proc emoticonic_html {text} {
    foreach {ei begin end} [list *  <strong> </strong> \
                                 '  <b>      </b>      \
                                {"} <b>      </b>] {
        set body ""
        while {[set x [string first "|$ei" $text]] >= 0} {
            if {$x > 0} {
                append body [string range $text 0 [expr $x-1]]
            }
            append body "$begin"
            set text [string range $text [expr $x+2] end]
            if {[set x [string first "|" $text]] < 0} {
                error "missing close for |$ei"
            }
            if {$x > 0} {
                append body [string range $text 0 [expr $x-1]]
            }
            append body "$end"
            set text [string range $text [expr $x+1] end]
        }
        append body $text
        set text $body
    }

    return $text
}


#
# slides sub-mode
#

catch {
    package require Trf
}

set leftGif \
"R0lGODlhFAAWAKEAAP///8z//wAAAAAAACH+TlRoaXMgYXJ0IGlzIGluIHRoZSBwdWJsaWMgZG9t
YWluLiBLZXZpbiBIdWdoZXMsIGtldmluaEBlaXQuY29tLCBTZXB0ZW1iZXIgMTk5NQAh+QQBAAAB
ACwAAAAAFAAWAAACK4yPqcvN4h6MSViK7MVBb+p9TihKZERqaDqNKfbCIdd5dF2CuX4fbQ9kFAAA
Ow=="

set rightGif \
"R0lGODlhFAAWAKEAAP///8z//wAAAAAAACH+TlRoaXMgYXJ0IGlzIGluIHRoZSBwdWJsaWMgZG9t
YWluLiBLZXZpbiBIdWdoZXMsIGtldmluaEBlaXQuY29tLCBTZXB0ZW1iZXIgMTk5NQAh+QQBAAAB
ACwAAAAAFAAWAAACK4yPqcsd4pqAUU1az8V58+h9UtiFomWeSKpqZvXCXvZsdD3duF7zjw/UFQAA
Ow=="

set upGif \
"R0lGODlhFAAWAKEAAP///8z//wAAAAAAACH+TlRoaXMgYXJ0IGlzIGluIHRoZSBwdWJsaWMgZG9t
YWluLiBLZXZpbiBIdWdoZXMsIGtldmluaEBlaXQuY29tLCBTZXB0ZW1iZXIgMTk5NQAh+QQBAAAB
ACwAAAAAFAAWAAACI4yPqcvtD6OcTQgarJ1ax949IFiNpGKaSZoeLIvF8kzXdlAAADs="

proc end_rfc_slides {} {
    global ifile
    global passno indexpg
    global slideno slidewd slidemx sildenm

    if {$passno != 2} {
        end_page_slides
        return 1
    }

    set slidemx $slideno
    set slidewd [expr int(log10($slideno))+1]
    foreach file [glob -nocomplain [file rootname $ifile]-*.html] {
        catch { file delete -force $file }
    }

    if {![string compare [info commands base64] base64]} {
        foreach gif {left right up} {
            global ${gif}Gif

            if {![file exists ${gif}.gif]} {
                set fd [open ${gif}.gif {WRONLY CREAT TRUNC}]
                fconfigure $fd -translation binary

                puts -nonewline $fd [base64 -mode decode -- [set ${gif}Gif]]

                close $fd
            }
        }
    }

    return 0
}

proc front_slides_begin {left right top bottom title} {
    global passno indexpg
    global stdout

    global slideno slidewd slidemx slidenm slideft

    set slideno 0
    start_page_slides [set slideft [lindex $title 0]]

    if {$passno == 2} {
        return 0
    }

    set size 4
    puts $stdout "<br><br><br><br><p align=\"right\">"
    puts $stdout "<table width=\"75%\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\">"
    puts $stdout "<tr><td>"
    puts $stdout "<table width=\"100%\" border=\"0\" cellpadding=\"2\" cellspacing=\"1\">"
    set left [munge_long $left]
    set right [munge_long $right]
    set lc ""
    set rc ""
    foreach l $left r $right {
        if {[string compare $l ""]} {
            set l $l
        } else {
            set l "&nbsp;"
        }
        if {[string compare $r ""]} {
            set r $r
        } else {
            set r "&nbsp;"
        }
        puts $stdout "<tr valign=\"top\">"
        puts $stdout "<td width=\"33%\"><font color=\"#006600\" size=\"+$size\">$l</font></td>"
        puts $stdout "<td width=\"33%\"><font color=\"#006600\" size=\"+$size\">$r</font></td>"
        puts $stdout "</tr>"

        set size 3
    }
    puts $stdout "</table>"
    puts $stdout "</td></tr>"
    puts $stdout "</table>"
    puts $stdout "</p>"

    return 1
}

proc start_page_slides {{title ""}} {
    global passno indexpg
    global ifile
    global stdout
    global slideno slidewd slidemx slidenm slideft

    if {$passno < 3} {
        return
    }

    if {$slideno == 0} {
        catch { close $stdout }
        catch { file delete -force [file rootname].html }
    }

    set stdout [open [file rootname $ifile]-[set p [slide_foo $slideno]].html \
                     { WRONLY CREAT TRUNC }]

    if {[string compare $title ""]} {
        set slidenm $title
    } else {
        set title "$slidenm (continued)"
    }
    if {$slideno != 0} {
        append p ": "
    } else {
        set p ""
    }
    puts $stdout "<html><head><title>"
    pcdata_html $p$title
    puts $stdout "</title></head>"
    puts $stdout "<body text=\"#000000\" vlink=\"#006600\" alink=\"#ccddcc\" link=\"#006600\"\n      bgcolor=\"#ffffff\">"
    puts $stdout "<font face=\"arial, helvetica, sans\">"
    puts $stdout "<table height=\"100%\" cellSpacing=0 cellPadding=0 width=\"100%\" border=0>"
    puts $stdout "<tbody><tr><td valign=top>"

    puts $stdout "<table height=\"100%\" cellSpacing=\"0\" cellPadding=\"0\" width=\"100%\" border=\"0\">"
    puts $stdout "<tbody><tr><td valign=top>"
    puts $stdout "<p><font color=\"#006600\" size=\"+5\">$title</font></p>"

    puts $stdout "<br><br>"
    puts $stdout "<font size=\"+3\">"
}

proc end_page_slides {} {
    global passno indexpg
    global ifile
    global stdout
    global slideno slidewd slidemx slidenm slideft

    if {$passno < 3} {
        incr slideno
        return 0
    }

    set up [file rootname [file tail $ifile]]-[slide_foo 0].html
    if {[set left [expr $slideno-1]] < 0} {
        set left $slidemx
    }
    set left [file rootname [file tail $ifile]]-[slide_foo $left].html
    if {[set right [expr $slideno+1]] > $slidemx} {
        set right 0
    }
    set right [file rootname [file tail $ifile]]-[slide_foo $right].html

    puts $stdout "</font>"
    puts $stdout "</td></tr></tbody>"
    puts $stdout "</table>"
    puts $stdout "</td><td valign=\"bottom\" align=\"right\">"
    puts -nonewline \
         $stdout "<p align=\"right\"><nobr>"
    puts -nonewline \
         $stdout "<a href=\"$left\"><img src=\"left.gif\"   border=\"0\" width=\"20\" height=\"22\"></img></a>"
    puts -nonewline \
         $stdout "<a href=\"$up\"><img src=\"up.gif\"       border=\"0\" width=\"20\" height=\"22\"></img></a>"
    puts -nonewline \
         $stdout "<a href=\"$right\"><img src=\"right.gif\" border=\"0\"></img></a>"
    puts $stdout "</nobr></p>"
    puts $stdout "</td></tr>"
    puts $stdout "<tr><td align=\"right\" colspan=2>"
    puts $stdout "<font color=\"#006600\" size=\"-3\">"
    pcdata_html $slideft
    pcdata_html "</font>"
    puts $stdout "</td></tr></tbody>"
    puts $stdout "</table>"
    puts $stdout "</font></body></html>"

    catch { close $stdout }
    set stdout ""

    incr slideno
    return 1
}

proc slide_pre {text} {
    global passno indexpg
    global stdout

    if {$passno < 3} {
        return 0
    }

    puts $stdout "<pre>$text</pre>"

    return 1
}

proc slide_foo {n} {
    global slideno slidewd slidemx slidenm slideft

    return [format %*.*d $slidewd $slidewd $n]
}


#
# nroff output
#

proc rfc_nr {irefs copying} {
    global options copyrightP
    global funding
    global header footer lineno pageno blankP
    global indents indent lastin
    global nofillP
    global indexpg

    end_page_nr

    if {[llength $irefs] > 0} {
        set indexpg $pageno

        if {$lastin != 0} {
            write_it ".in [set lastin [set indent 0]]"
            set indents {}
        }
        write_line_nr "Index"

        foreach iref $irefs {
            foreach {L item subitem pages} $iref { break }

            if {[string compare $L ""]} {
                write_line_nr ""
                write_line_nr $L           
            }

            if {[string compare $item ""]} {
                write_text_nr $item
                if {[string compare $subitem ""]} {
                    flush_text
                    push_indent 3
                    write_text_nr "   $subitem"
                }
            } else {
                push_indent 3
                write_text_nr "   $subitem"
            }

            set s "  "
            foreach page $pages {
                write_text_nr "$s$page"
                set s ", "
            }
            pop_indent
            flush_text  
        }

        end_page_nr
    }

    if {(!$options(.PRIVATE)) && $copyrightP} {
        set result $pageno

        if {$lastin != 3} {
            write_it ".in [set lastin [set indent 3]]"
            set indents {}
        }
        write_it ".ti 0"
        write_line_nr "Full Copyright Statement"

        foreach para $copying {
            write_line_nr ""
            pcdata_nr $para
        }
        write_line_nr ""

        if {![have_lines 4]} {
            end_page_nr
        }

        write_it ".ti 0"
        write_line_nr "Acknowledgement"
        write_line_nr ""
        pcdata_nr $funding

        flush_text
    } else {
        set result ""
    }

    return $result
}

proc front_nr_begin {left right top bottom title status copying} {
    global options copyrightP
    global ifile mode ofile
    global header footer lineno pageno blankP
    global eatP nofillP indent lastin
    global passno indexpg

    set lineno 1
    set pageno 1
    set blankP 0
    set eatP 0
    set lastin -1

    write_it [clock format [clock seconds] \
                    -format ".\\\" automatically generated by xml2rfc v1.10 on %d %b %Y %T +0000" \
                    -gmt true]
    write_it ".\\\" "
    write_it ".pl 10.0i"
    write_it ".po 0"
    write_it ".ll 7.2i"
    write_it ".lt 7.2i"
    write_it ".nr LL 7.2i"
    write_it ".nr LT 7.2i"
    write_it ".ds LF [chars_expand [lindex $bottom 0]]"
    write_it ".ds RF FORMFEED\[Page %]"
    write_it ".ds CF [chars_expand [lindex $bottom 1]]"
    write_it ".ds LH [chars_expand [lindex $top 0]]"
    write_it ".ds RH [chars_expand [lindex $top 2]]"
    write_it ".ds CH [chars_expand [lindex $top 1]]"
    write_it ".hy 0"
    write_it ".ad l"
    write_it ".nf"
    set nofillP -1

    if {$passno == 2} {
        set indexpg 0
    }

    incr lineno 4
    set left [munge_long $left]
    set right [munge_long $right]
    foreach l $left r $right {
        set l [chars_expand $l]
        set r [chars_expand $r]
        set len [expr 72-[string length $l]]
        write_line_nr [format %s%*.*s $l $len $len $r]
    }
    write_line_nr "" -1
    write_line_nr "" -1

    foreach line $title {
        write_text_nr [chars_expand $line] c
    }

    write_line_nr "" -1

    if {$lastin != $indent} {
        write_it ".in [set lastin $indent]"
    }

    if {!$options(.PRIVATE)} {
        write_it ".ti 0"
        write_line_nr "Status of this Memo"
        foreach para $status {
            write_line_nr ""
            pcdata_nr $para
        }
    }

    if {(!$options(.PRIVATE)) && $copyrightP} {
        write_line_nr "" -1
        write_it ".ti 0"
        write_line_nr "Copyright Notice"
        write_line_nr "" -1
        pcdata_nr $copying
    }
    incr lineno -1
}

proc front_nr_end {toc irefP} {
    global options
    global header footer lineno pageno blankP
    global indexpg
    global nofillP

    if {$options(.TOC)} {
        set last [lindex $toc end]
        if {[string compare [lindex $last 1] "Full Copyright Statement"]} {
            set last ""
        } else {
            set toc [lreplace $toc end end]
        }
        if {$irefP} {
            lappend toc [list "" Index $indexpg]
        }
        if {[string compare $last ""]} {
            lappend toc $last
        }

        if {(![have_lines [expr [llength $toc]+3]]) || ($lineno > 17)} {
            end_page_nr
        } else {
            write_line_nr "" -1
        }
        write_it ".ti 0"
        write_line_nr "Table of Contents"
        write_line_nr "" -1

        write_it ".nf"
        set nofillP 1

        set len1 0
        set len2 0
        foreach c $toc {
            if {[set x [string length [lindex $c 0]]] > $len1} {
                set len1 $x
            }
            if {[set x [string length [lindex $c 2]]] > $len2} {
                set len2 $x
            }
        }
        set mid [expr 72-($len1+$len2+5)]

        foreach c $toc {
            if {!$options(.SUBCOMPACT)} {
                if {[string last . [lindex $c 0]] \
                        == [expr [string length [lindex $c 0]]-1]} {
                    write_line_txt ""
                }
            }
            set s1 [format "%-*.*s " $len1 $len1 [lindex $c 0]]
            set s2 [format " %*.*s" $len2 $len2 [lindex $c 2]]
            set title [chars_expand [string trim [lindex $c 1]]]
            while {[set i [string length $title]] > $mid} {
                set phrase [string range $title 0 [expr $mid-1]]
                if {[set x [string last " " $phrase]] < 0} {
                    if {[set x [string first " " $title]] < 0} {
                        break
                    }
                }
                write_toc_nr $s1 [string range $title 0 [expr $x-1]] \
                        [format " %-*.*s" $len2 $len2 ""] $mid 0
                set s1 [format "   %-*.*s " $len1 $len1 ""]
                set title [string trimleft [string range $title $x end]]
            }
            write_toc_nr $s1 $title $s2 $mid 1
        }
    }

    if {($options(.TOC) || !$options(.COMPACT))} {
        end_page_nr
    }
}

proc write_toc_nr {s1 title s2 len dot} {
    set x [string length $title]
    if {($dot) && ($x < $len)} {
        if {$x%2} {
            append title " "
            incr x
        }
        while {$x < $len} {
            append title " ."
            incr x 2
        }
    }

    write_line_nr [format "%s%-*.*s%s" $s1 $len $len $title $s2]
}

proc abstract_nr {} {
    write_line_nr "" -1
    write_it ".ti 0"
    write_line_nr "Abstract"
    write_line_nr "" -1
}

proc note_nr {title depth} {
    write_line_nr "" -1
    write_it ".ti 0"
    write_line_nr [chars_expand $title]
    write_line_nr "" -1
}

proc section_nr {prefix top title lines anchor} {
    global options
    global header footer lineno pageno blankP
    global indents indent lastin

    if {($top && !$options(.COMPACT)) || (![have_lines [expr $lines+5]])} {
        end_page_nr
    } else {
        write_line_nr "" -1
    }

    indent_text_nr "$prefix " 0
    write_text_nr [chars_expand $title]
    flush_text
    pop_indent

    if {$lastin != 3} {
        write_it ".in [set lastin [set indent 3]]"
        set indents {}
    }

    return $pageno
}

proc t_nr {tag counter style hangText editNo} {
    global options
    global eatP

    if {![string compare $tag end]} {
        return
    }

    if {[string compare $counter ""]} {
        set pos [pop_indent]
        set l [split $counter .]
        set left -1
        switch -- $style {
            numbers {
                set counter "[lindex $l end]. "
            }

            symbols {
                set counter "[lindex { - o * + } [expr [llength $l]%4]] "
            }

            hanging {
                set counter "$hangText "
                set left ""
            }

            default {
                set counter "  "
            }
        }
        flush_text
        if {$options(.EDITING)} {
            write_editno_nr $editNo
        } elseif {!$options(.SUBCOMPACT)} {
            write_line_nr ""
        }
        indent_text_nr [format "%0s%-[expr $pos-0]s" "" $counter] $left
        pop_indent
        push_indent $pos
    } else {
        if {$options(.EDITING)} {
            write_editno_nr $editNo
        } else {
            write_line_nr ""
        }
    }

    set eatP 1
}

proc list_nr {tag counters style hangIndent hangText} {
    global options
    global eatP
    global indent lastin

    switch -- $tag {
        begin {
            switch -- $style {
                numbers {
                    set i 0
                    foreach counter $counters {
                        if {[set j [string length \
                                           [lindex [split $counter .] end]]] \
                                > $i} {
                            set i $j
                        }
                    }
                    incr i 1
                }

                format {
                    set i [expr [string length $hangText]-1]
                }

                default {
                    set i 1
                }
            }
            if {[incr i 2] > $hangIndent} {
                push_indent [expr $i+0]
            } else {
                push_indent [expr $hangIndent+0]
            }
        }

        end {
            flush_text
            if {!$options(.SUBCOMPACT)} {
                write_line_nr ""
            }
            pop_indent

            set eatP 1

            if {$lastin != $indent} {
                write_it ".in [set lastin $indent]"
            }
        }
    }
}

proc figure_nr {tag lines anchor src title} {
    global counter depth elemN elem passno stack xref

    switch -- $tag {
        begin {
            if {[string compare $title ""]} {
                incr lines 8
            }
            if {![have_lines $lines]} {
                end_page_nr
            }
            flush_text
            if {[string compare $title ""]} {
                write_line_nr ""
                write_line_nr \
                    "---------------------------------------------------------------------"
                write_line_nr ""
            }
        }

        end {
            if {[string compare $title ""]} {
                if {[string compare $anchor ""]} {
                    array set av $xref($anchor)
                    set prefix "Figure $av(value): "
                } else {
                    set prefix ""
                }
                write_line_nr ""
                write_text_nr "$prefix$title" c
                write_line_nr ""
                write_line_nr \
                    "---------------------------------------------------------------------"
                write_line_nr ""
            }
        }
    }
}

proc preamble_nr {tag {editNo ""}} {
    global options

    switch -- $tag {
        begin {
            if {$options(.EDITING)} {
                write_editno_nr $editNo
            } else {
                write_line_nr ""
            }
        }
    }
}

proc postamble_nr {tag {editNo ""}} {
    global options
    global eatP

    switch -- $tag {
        begin {
            set eatP 1
            if {$options(.EDITING)} {
                write_editno_nr $editNo
            }
        }
    }
}

proc xref_nr {text av target} {
    global eatP

    array set attrs $av    

    switch -- $attrs(type) {
        section {
            set line "Section $attrs(value)"
        }

        appendix {
            set line "Appendix $attrs(value)"
        }

        figure {
            set line "Figure $attrs(value)"
        }

        default {
            set line "\[$attrs(value)\]"
        }
    }
    if {[string compare $text ""]} {
        switch -- $attrs(type) {
            section
                -
            appendix
                -
            figure {
                set line "[chars_expand $text] ($line)"
            }

            default {
                set line "[chars_expand $text]$line"
            }
        }       
    }
    write_text_nr $line

    set eatP 0
}

proc eref_nr {text counter target} {
    global eatP
    global erefs

    if {[string compare $text ""]} {
        set line "[chars_expand $text]"
    }
    if {([string first "#" $target] < 0) \
            && ([string compare $text $target])} {
        set erefs($counter) $target
        append line " \[$counter\]"
    }
    write_text_nr $line

    set eatP 0
}

proc iref_nr {item subitem} {
    global header footer lineno pageno blankP

    return $pageno
}

proc vspace_nr {lines} {
    global header footer lineno pageno blankP
    global eatP

    flush_text
    if {$lineno+$lines >= 51} {
        end_page_nr
    } else {
        while {$lines > 0} {
            incr lines -1

            write_it ""
            incr lineno
        }
    }

    set eatP 1
}

proc references_nr {tag {title ""} {erefP 0}} {
    global options
    global header footer lineno pageno blankP
    global nofillP lastin

    switch -- $tag {
        begin {
            if {$options(.COMPACT)} {
                write_line_nr ""
            } else {
                end_page_nr
            }
            if {$nofillP} {
                flush_text
                write_it ".fi"
                set nofillP 0
                set lastin -1
            }
            write_it ".ti 0"
            write_line_nr $title

            return $pageno
        }

        end {
            if {$erefP} {
                erefs_nr
            } else {
                flush_text
            }
        }
    }
}

proc erefs_nr {{title ""}} {
    global erefs
    global options
    global nofillP lastin

    if {[string compare $title ""]} {
        if {$options(.COMPACT)} {
            write_line_nr ""
        } else {
            end_page_nr
        }
        if {$nofillP} {
            flush_text
            write_it ".fi"
            set nofillP 0
            set lastin -1
        }
        write_it ".ti 0"
        write_line_nr $title
    }

    set names  [lsort -integer [array names erefs]]
    set width [expr [string length [lindex $names end]]+2]
    foreach eref $names {
        write_line_nr ""

        indent_text_nr "[format %-*.*s $width $width "\[$eref\]"]  " -1

        write_url $erefs($eref)
        flush_text

        pop_indent
    }

    flush_text
}

proc reference_nr {prefix names title series date anchor target target2 
                   width} {
    write_line_nr ""

    incr width 2
    indent_text_nr "[format %-*.*s $width $width "\[$prefix\]"]  " -1

    set hack $names
    set names ""
    foreach name $hack {
        if {[string compare [lindex $name 0] ""]} {     
            lappend names $name
        }
    }
    set nameN [llength $names]

    set s ""
    set nameA 1
    foreach name $names {
        incr nameA
        write_text_nr $s[chars_expand [lindex $name 0]]
        if {$nameA == $nameN} {
            set s " and "
        } else {
            set s ", "
        }
    }
    write_text_nr "$s\"[chars_expand $title]\""
    foreach serial $series {
        if {[regexp -nocase -- "internet-draft (draft-.*)" $serial x n] == 1} {
            set serial "$n (work in progress)"
        }
        write_text_nr ", [chars_expand $serial]"
    }
    if {[string compare $date ""]} {
        write_text_nr ", $date"
    }
    if {[string compare $target ""]} {
        write_text_nr ", "
        write_url $target
    }
    write_text_nr .

    pop_indent
}

proc back_nr {authors} {
    global options
    global header footer lineno pageno blankP
    global indents indent lastin
    global nofillP
    global contacts

    set lines 5
    set author [lindex $authors 0]
    incr lines [llength [lindex $author 0]]
    incr lines [llength [lindex $author 1]]
    if {![have_lines $lines]} {
        end_page_nr
    } elseif {$lineno != 3} {
        write_line_nr "" -1
        write_line_nr "" -1
    }
    set result $pageno

    if {$lastin != $indent} {
        write_it ".in [set lastin $indent]"
    }
    write_it ".nf"
    set nofillP 1

    switch -- [llength $authors] {
        0 {
            return $result
        }

        1 {
            set s1 "'s"
            set s2 ""
        }

        default {
            set s1 "s'"
            set s2 "es"
        }
    }
    set s "Author$s1 Address$s2"

    set firstP 1
    foreach author $authors {
        set block1 [lindex $author 0]
        set block2 [lindex $author 1]

        set lines 3
        incr lines [llength $block1]
        incr lines [llength $block2]
        if {![have_lines $lines]} {
            end_page_nr
        }

        if {[string compare $s ""]} {
            write_it ".ti 0"
            write_line_nr $s
            set s ""
        } else {
            write_line_nr "" -1
        }
        write_line_nr "" -1

        foreach line $block1 {
            write_line_nr [chars_expand $line]
        }

        if {[llength $block2] > 0} {
            write_line_nr ""
            foreach contact $block2 {
                set key [lindex $contact 0]
                set value [lindex [lindex $contacts \
                                          [lsearch0 $contacts $key]] 1]
                set value [format %-6s $value:]
                write_line_nr "$value [chars_expand [lindex $contact 1]]"
            }
        }
    }

    return $result
}

proc pcdata_nr {text {pre 0}} {
    global eatP
    global nofillP lastin
    global options

    if {(!$pre) && ($eatP)} {
        set text [string trimleft $text]
    }
    set eatP 0

    if {!$pre} {
        regsub -all "\n\[ \t\n\]*" $text "\n" text
        regsub -all "\[ \t\]*\n\[ \t\]*" $text "\n" text
        set prefix ""

        if {$options(.EMOTICONIC)} {
            set text [emoticonic_txt $text]
        }
    }

    if {$nofillP != $pre} {
        flush_text
        if {$pre} {
            write_it ".nf"
        } else {
            write_it ".fi"
            set lastin -1
        }
        set nofillP $pre
    }
    foreach line [split $text "\n"] {
        set line [chars_expand $line]
        if {$pre} {
            write_line_nr [string trimright $line] 1
        } else {
            write_pcdata_nr $prefix$line
            set prefix " "
        }
    }
}


proc start_page_nr {} {
    global stdout
    global header footer lineno pageno blankP

    set lineno 3
    set blankP 1
}

proc end_page_nr {} {
    global stdout
    global header footer lineno pageno blankP

    flush_text

    if {$lineno <= 3} {
        return
    }

    incr pageno
    set lineno 0

    write_it ".bp"
}

proc indent_text_nr {prefix {left ""}} {
    global buffer
    global indents indent lastin
    global nofillP

    flush_text
    if {$nofillP} {
        write_it ".fi"
        set nofillP 0
        set lastin -1
    }

    if {![string compare $left ""]} {
        set left $indent
        while {![string compare [string index $prefix 0] " "]} {
            incr left
            set prefix [string range $prefix 1 end]
        }
        push_indent 3
    } elseif {$left < 0} {
        set left $indent
        push_indent [string length $prefix]
    } else {
        push_indent [expr $left+[string length $prefix]-$indent]
    }
    if {$lastin != $indent} {
        write_it ".in [set lastin $indent]"
    }
    if {$indent != $left} {
        write_it ".ti $left"
    }
    set buffer [format %*.*s $left $left ""]
    write_text_nr $prefix
}

proc write_pcdata_nr {text} {
    global buffer
    global indents indent

    if {![string compare $buffer ""]} {
        set buffer [format %*.*s $indent $indent ""]    
    }
    append buffer $text
    set buffer [two_spaces $buffer]

    write_text_nr ""
}

proc write_editno_nr {editNo} {
    global buffer
    global indents indent

    if {[string compare $buffer ""]} {
        flush_text
    }
    write_it ".ti 0"
    write_it <$editNo>
    write_it ".br"
}

proc write_text_nr {text {direction l}} {
    global buffer
    global indents indent lastin

    if {![string compare $direction c]} {
        flush_text
    }
    if {(![string compare $buffer$direction l]) \
            && ($lastin != $indent)} {
        write_it ".in [set lastin $indent]"
    }
    if {![string compare $buffer ""]} {
        set buffer [format %*.*s $indent $indent ""]    
    }
    append buffer $text

    set flush [string compare $direction l]
    while {([set i [string length $buffer]] > 72) || ($flush)} {
        if {$i > 72} {
            set x [string last " " [set line [string range $buffer 0 72]]]
            set y [string last "-" [string range $line 0 71]]
            set z [string last "/" [string range $line 0 71]]
            if {$y < $z} {
                set y $z
            }
            if {$x < $y} {
                set x $y
            }
            if {$x < 0} {
                set x [string last " " $buffer]
                set y [string last "-" $buffer]
                set z [string last "/" $buffer]
                if {$y > $z} {
                    set y $z
                }
                if {$x > $y} {
                    set x $y
                }
            }
            if {$x < 0} {
                set x $i
            } elseif {($x == $y) || ($x == $z)} {
                incr x
            } elseif {$x+1 == $indent} {
                set x $i
            }
            set text [string range $buffer 0 [expr $x-1]]
            set rest [string trimleft [string range $buffer $x end]]
        } else {
            set text $buffer
            set rest ""
        }
        set buffer ""

        if {![string compare $direction c]} {
            write_it ".ce"
        }
        write_line_nr [string trimleft $text]

        if {[string compare $rest ""]} {
            set buffer [format %*.*s%s $indent $indent "" $rest]
        } else {
            break
        }
    }
}

proc write_line_nr {line {pre 0}} {
    global stdout
    global header footer lineno pageno blankP
    global buffer
    global indents indent lastin
    global nbsp

    flush_text
    if {$lineno == 0} {
        start_page_nr
    }
    if {![set x [string compare $line ""]]} {
        set blankO $blankP
        set blankP 1
        if {($blankO) && (!$pre || $lineno == 3)} {
            return
        }
    } else {
        set blankP 0
    }
    if {($pre) && ($x) && ($lastin != 3)} {
        write_it ".in [set lastin 3]"
    }
    regsub -all "\\\\" $line "\\\\\\" line
    regsub -all "$nbsp" $line "\\\\0" line
    if {[string first "." $line] == 0} {
        set line "\\&$line"
    }
    write_it $line
    incr lineno
    if {$lineno >= 51} {
        end_page_nr
    }
}


#
# low-level formatting
#


global contacts

set contacts { {phone Phone} {facsimile Fax} {email EMail} {uri URI} }


global buffer indent

set buffer ""
set indent 3
set indents {}

global rfcTxtHome idTxtHome

set rfcTxtHome ftp://ftp.isi.edu/in-notes
set idTxtHome http://www.ietf.org/internet-drafts


global oentities

# &amp; must always be last...
set oentities { {&lt;}     {<} {&gt;}  {>}
                {&apos;}   {'} {&quot;} {"}
                {&#8211;}  {-} {&#151;} {--}
                {&endash;} {-} {&emdash;} {--}
                {&amp;} {\&} }


proc push_indent {pos} {
    global indent indents

    lappend indents $pos
    incr indent $pos
}

proc pop_indent {} {
    global indent indents

    set pos [lindex $indents end]
    incr indent -$pos
    set indents [lreplace $indents end end]

    return $pos
}

proc flush_text {} {
    global buffer
    global mode
    global indents indent lastin

    if {[string compare $buffer ""]} {
        set rest $buffer
        set buffer ""
        if {[string compare $mode txt]} {
            set rest [string trim $rest]
        }
        write_line_$mode $rest
    }
}

proc munge_long {lines} {
    global mode

    set result ""

    foreach buffer $lines {
        set linkP 0
        if {(![string compare $mode html]) \
                && (([string match Obsoletes:* $buffer])
                        || ([string match Updates:* $buffer]))} {
            set linkP 1
        }
        while {[set i [string length $buffer]] > 34} {
            set line [string range $buffer 0 34]
            if {[set x [string last " " $line]] < 0} {
                if {[set x [string first " " $buffer]] < 0} {
                    break
                }
            }
            set line [string range $buffer 0 [expr $x-1]]
            if {$linkP} {
                set line [munge_line $line]
            }
            lappend result $line
            set buffer [string trimleft [string range $buffer $x end]]
        }

        if {$linkP} {
            set buffer [munge_line $buffer]
        }
        lappend result $buffer
    }

    return $result
}

proc munge_line {line} {
    global rfcTxtHome
    global rfcHtmlHome

    if {[set y [string first : $line]] >= 0} {
        set start [string range $line 0 $y]
        set line [string range $line [expr $y+1] end]
    } else {
        set start ""
    }

    set s ""
    foreach n [split $line ,] {
        set n [string trim $n]
        if {[catch { set rfcHtmlHome }]} {
            append start $s "<a href='$rfcTxtHome/rfc$n.txt'>$n</a>"
        } else {
            append start $s "<a href='$rfcHtmlHome/rfc$n.html'>$n</a>"
        }
        set s ", "
    }

    return $start
}

proc write_url {url} {
    global mode

    write_text_$mode <$url>
}

proc have_lines {cnt} {
    global header footer lineno pageno blankP

    if {($cnt < 40) && ($lineno+$cnt > 51)} {
        return 0
    }
    return 1
}

proc write_it {line} {
    global passno
    global options
    global stdout
    global header footer lineno pageno blankP

    if {(!$options(.TOC)) || ($passno == 3)} {
        puts $stdout $line
    }
}

proc chars_expand {text {flatten 1}} {
    global entities

    foreach {entity chars} $entities {
        regsub -all -nocase $entity $text $chars text
    }
    if {$flatten} {
        regsub -all "\n\[ \t\]*" $text " " text
    }

    return $text
}


#
# xml2ref support
#

namespace eval ref {
    variable ref
    array set ref { uid 0 }

    variable parser [xml::parser]

    variable context
    #              element       verbatim        beginF  endF
    set context { {dummy/-1}
                  {rfc/0         no              yes     yes}
                  {front/1}
                  {title/2}
                  {author/2}
                  {organization/3}
                  {address/3}
                  {postal/4}
                  {street/5}
                  {city/5}
                  {region/5}
                  {code/5}
                  {country/5}
                  {phone/4}
                  {facsimile/4}
                  {email/4}
                  {uri/4}
                  {date/2}
                  {area/2}
                  {workgroup/2}
                  {keyword/2}
                  {abstract/2    yes}
                  {note/2        yes}
                }

    namespace export init fin transform
}

proc ref::init {} {
    variable ref

    set token [namespace current]::[incr ref(uid)]

    variable $token
    upvar 0 $token state

    array set state {}

    return $token
}

proc ref::fin {token} {
    variable $token
    upvar 0 $token state

    foreach name [array names state] {
        unset state($name)
    }
    unset $token
}

proc ref::transform {token file} {
    global errorCode errorInfo

    variable $token
    upvar 0 $token state

    array set emptyA {}

    variable parser
    $parser configure \
            -elementstartcommand    "ref::element_start $token" \
            -elementendcommand      "ref::element_end   $token" \
            -characterdatacommand   "ref::cdata         $token" \
            -entityreferencecommand ""                          \
            -errorcommand           ref::oops                   \
            -entityvariable         emptyA                      \
            -final                  yes                         \
            -reportempty            no

    set fd [open $file { RDONLY }]
    set data [prexml [read $fd] [file dirname $file]]

    if {[catch { close $fd } result]} {
        log::entry $logT system $result
    }

    set state(stack)    ""
    set state(body)     ""
    set state(verbatim) 0
    set state(silent) 0

    set code [catch { $parser parse $data } result]
    set ecode $errorCode
    set einfo $errorInfo

    switch -- $code {
        0 {
            set result $state(body)
        }

        1 {
            if {[llength $state(stack)] > 0} {
                set text "File:    $file\nContext: "
                foreach frame $state(stack) {
                    catch { unset attrs }
                    append text "\n    <[lindex $frame 0]"
                    foreach {k v} [lindex $frame 1] {
                        regsub -all {"} $v {&quot;} v
                        append text " $k=\"$v\""
                    }
                    append text ">"
                }
                append result "\n\n$text"
            }
        }
    }

    unset state(stack)    \
          state(body)     \
          state(verbatim) \
          state(silent)

    return -code $code -errorinfo $einfo -errorcode $ecode $result
}

proc ref::element_start {token name {av {}}} {
    variable $token
    upvar 0 $token state

    variable context

    set depth [llength $state(stack)]

    if {[set idx [lsearch -glob $context $name/$depth*]] >= 0} {
        set info [lindex $context $idx] 
        if {[string compare [lindex $info 0] $name/$depth]} {
            set idx -1
        } elseif {![string compare [lindex $info 1] yes]} {
            set state(verbatim) 1
        }
    }

    set state(silent) 0
    if {($idx < 0) && ($state(verbatim))} {
        set idx 0
        set info ""
        if {[lsearch -exact {xref eref iref vspace} $name] >= 0} {
            set state(silent) 1
        }
    }

    if {$idx >= 0} {
        if {![string compare [lindex $info 2] yes]} {
            ref::start_$name $token $av
        } elseif {!$state(silent)} {
            append state(body) "\n<$name"
            foreach {n v} $av {
                regsub -all {'} $v {\&apos;} v
                regsub -all {"} $v {\&quot;} v
                append state(body) " $n='$v'"
            }
            append state(body) >
        }
    }

    lappend state(stack) [list $name $av $idx ""]
}

proc ref::element_end {token name} {
    variable $token
    upvar 0 $token state

    variable context

    set frame [lindex $state(stack) end]
    set state(stack) [lreplace $state(stack) end end]

    if {[set idx [lindex $frame 2]] >= 0} {
        set info [lindex $context $idx]
        if {![string compare [lindex $info 3] yes]} {
            ref::end_$name $token $frame
        } elseif {!$state(silent)} {
            append state(body) </$name>
        }

        if {![string compare [lindex $info 1] yes]} {
            set state(verbatim) 0
        }
    }
    set state(silent) 0
}

proc ref::cdata {token text} {
    variable $token
    upvar 0 $token state

    if {[string length [string trim $text]] <= 0} {
        return
    }

    set frame [lindex $state(stack) end]
    if {[set idx [lindex $frame 2]] < 0} {
        return
    }

    regsub -all "\r" $text "\n" text

    append state(body) $text
}

proc ref::oops {args} {
    return -code error [join $args " "]
}

proc ref::start_rfc {token av} {
    variable $token
    upvar 0 $token state

    array set rfc [list obsoletes "" updates "" category info seriesNo ""]
    array set rfc $av
    if {[catch { set rfc(number) }]} {
        ref::oops "missing number attribute in rfc element"
    }

    set state(body) "<?xml version='1.0'?>
<!DOCTYPE reference SYSTEM 'rfc2629.dtd'>

<reference anchor='RFC[format %04d $rfc(number)]'>
"
}

proc ref::end_rfc {token frame} {
    variable $token
    upvar 0 $token state

    array set rfc [list obsoletes "" updates "" category info seriesNo ""]
    array set rfc [lindex $frame 1]

    append state(body) "

"
    if {([string compare [set x $rfc(category)] info]) \
            && ([string compare [set y $rfc(seriesNo)] ""])} {
        append state(body) "<seriesInfo name='[string toupper $x]' "
        append state(body) "value='$y' />
"
    }
    append state(body) "<seriesInfo name='RFC' value='$rfc(number)' />
</reference>
"
}


#
# tclsh/wish linkage
#


global guiP
if {[info exists guiP]} {
    return
}
set guiP 0
if {![info exists tk_version]} {
    if {$tcl_interactive} {
        set guiP -1
        puts stdout ""
        puts stdout "invoke as \"xml2rfc   input-file output-file\""
        puts stdout "       or \"xml2txt   input-file\""
        puts stdout "       or \"xml2html  input-file\""
        puts stdout "       or \"xml2nroff input-file\""
    }
} elseif {[llength $argv] > 0} {
    switch -- [llength $argv] {
        2 {
            set file [lindex $argv 1]
            if {![string compare $tcl_platform(platform) windows]} {
                set f ""
                foreach c [split $file ""] {
                    switch -- $c {
                        "\\" { append f "\\\\" }

                        "\a" { append f "\\a" }

                        "\b" { append f "\\b" }

                        "\f" { append f "\\f" }

                        "\n" { append f "\\n" }

                        "\r" { append f "\\r" }

                        "\v" { append f "\\v" }

                        default {
                            append f $c
                        }
                    }
                }
                set file $f
            }

            eval [file tail [file rootname [lindex $argv 0]]] $file
        }

        3 {
            xml2rfc [lindex $argv 1] [lindex $argv 2]
        }
    }

    exit 0
} else {
    set guiP 1

    proc convert {w} {
        if {![string compare [set input [.input.ent get]] ""]} {
            tk_dialog .error "xml2rfc: oops!" "no input filename specified" \
                      error 0 OK
            return
        }
        set output [.output.ent get]

        if {[catch { xml2rfc $input $output } result]} {
            tk_dialog .error "xml2rfc: oops!" $result error 0 OK
        }
    }

    proc fileDialog {w ent operation} {
        set input {
            {"XML files"                .xml                    }
            {"All files"                *                       }
        }
        set output {
            {"HTML files"               .html                   }
            {"NRoff files"              .nr                     }
            {"TeXT files"               .txt                    }
        }
        if {![string compare $operation "input"]} {
            set file [tk_getOpenFile -filetypes $input -parent $w]
        } else {
            if {[catch { set input [.input.ent get] }]} {
                set input Untitled
            } else {
                set input [file rootname $input]
            }
            set file [tk_getSaveFile -filetypes $output -parent $w \
                            -initialfile $input -defaultextension .txt]
        }
        if [string compare $file ""] {
            $ent delete 0 end
            $ent insert 0 $file
            $ent xview end
        }
    }

    eval destroy [winfo child .]

    wm title . xml2rfc
    wm iconname . xml2rfc
    wm geometry . +300+300

    label .msg -font "Helvetica 14" -wraplength 4i -justify left \
          -text "Convert XML to RFC"
    pack .msg -side top

    frame .buttons
    pack .buttons -side bottom -fill x -pady 2m
    pack \
        [button .buttons.code -text Convert -command "convert ."] \
        [button .buttons.dismiss -text Quit -command "destroy ."] \
        -side left -expand 1
    
    foreach i {input output} {
        set f [frame .$i]
        label $f.lab -text "Select $i file: " -anchor e -width 20
        entry $f.ent -width 20
        button $f.but -text "Browse ..." -command "fileDialog . $f.ent $i"
        pack $f.lab -side left
        pack $f.ent -side left -expand yes -fill x
        pack $f.but -side left
        pack $f -fill x -padx 1c -pady 3
    }
}
