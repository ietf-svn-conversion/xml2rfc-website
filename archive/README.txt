

The README file                                                  M. Rose
                                                  Invisible Worlds, Inc.
                                                         August 22, 2001


                              xml2rfc v1.7


1. Introduction

   This is a package to convert memos written in XML to the RFC format.

   If you don't want to install any software, you can use the web-based
   service[2].

2. Requirements

2.1 Tcl/Tk version 8

   You need to have Tcl/Tk version 8 running on your system.  Tcl is a
   scripting language, Tk is Tcl with support for your windowing system.

   To get a source or binary distribution for your system, go to the
   Scriptics website[3] and install it.  If you get the binary
   distribution, this is pretty simple.

   Of course, you may already have Tcl version 8.  To find out, try
   typing this command from the shell (including the "MS-DOS Prompt"):

       % tclsh

   If the program launches, you're good to go with Tcl version 8.

   If you are running under a windowing system (e.g., X or Windows), you
   can also try:

       % wish

   If a new window comes up along with a "Console" window, then you're
   good to go with Tk version 8.












Rose                                                            [Page 1]

README                        xml2rfc v1.7                   August 2001


2.2 TclXML version 1.1.1

   You need to also have TclXML version 1.1.1 running on your system.
   TclXML is a Tcl package that parses XML.

   We've included a copy of TclXML in this release, you can also look in
   the TclXML site[4].

   For example, on Unix, you'd probably put the files somewhere under

       /usr/local/lib/tcl/

   or

       C:\Program Files\Tcl\lib\tcl8.0\TclXML-1.0\

   depending on whether you're on UNIX or Windows.

3. Testing

   Now test your installation.

3.1 Testing under a windowing system

   Type this command from the shell:

       % xml2rfc.tcl

   A new window should come up that looks like this:

       +------------------------------------------------------------+
       |                     Convert XML to RFC                     |
       |                                                            |
       |  Select input file: ____________________________  [Browse] |
       |                                                            |
       | Select output file: ____________________________  [Browse] |
       |                                                            |
       |               [Convert]               [Quit]               |
       |                                                            |
       +------------------------------------------------------------+

   Fill-in the blanks and click on [Convert].









Rose                                                            [Page 2]

README                        xml2rfc v1.7                   August 2001


3.2 Testing without a windowing system

   Type this command from the shell:

       % tclsh

   If the program launches, type this command to it:

       % source xml2rfc.tcl

   and you should see these four lines:

       invoke as "xml2rfc   inputfile outputfile"
              or "xml2txt   inputfile"
              or "xml2html  inputfile"
              or "xml2nroff inputfile"



































Rose                                                            [Page 3]

README                        xml2rfc v1.7                   August 2001


4. Next steps

   Read either rfc2629.txt [1] or rfc2629.html[5].  In particular,
   Section 3 has some good information.

4.1 Processing Instructions

   A "processing instruction" is a directive to an XML application.  If
   you want to give directives to xml2rfc, the PIs look like this:

       <?rfc keyword="value" ?>


4.1.1 Option Settings





































Rose                                                            [Page 4]

README                        xml2rfc v1.7                   August 2001


   The list of valid keywords are:

       keyword     default     meaning
       =======     =======     =======
       compact     no          when producing a .txt file, try to
                               conserve vertical whitespace

       subcompact  compact     if compact is "yes", then setting
                               this to "no" will make things a
                               little less compact

       toc         no          generate a table-of-contents

       editing     no          insert editing marks for ease of
                               discussing draft versions

       private     ""          produce a private memo rather than
                               an RFC or Internet-Draft.

       header      ""          override the leftmost header string

       footer      ""          override the center footer string

       slides      no          when producing an .html file, produce
                               multiple files for a slide show

       sortrefs    no          sort references

       symrefs     no          use anchors rather than numbers for
                               references

       background  ""          when producing an .html file, use this
                               image

   Remember, that as with everything else in XML, keywords and values
   are case-sensitive.

4.1.2 Include Files

   xml2rfc has an include-file facility, e.g.,

       <?rfc include="file" ?>

   xml2rfc will consult the $XML_LIBRARY environment variable for a
   search path of where to look for files.  (If this envariable isn't
   set, the directory containing the file that contains the include-file
   directive is used.)




Rose                                                            [Page 5]

README                        xml2rfc v1.7                   August 2001


   You can also have xml2rfc set this envariable directly, by including
   a file called ".xml2rfc.rc" in the directory where your main file is,
   e.g.,

   global env

   if {![info exists env(XML_LIBRARY)]} {
       set env(XML_LIBRARY) \
           ";\\home\\rfcs\\include;\\home\\rfcs\\bibxml"
   }
   set nativeD [file nativename $inputD]
   if {[lsearch [split $env(XML_LIBRARY) ";"] $nativeD] < 0} {
       set env(XML_LIBRARY) "$nativeD;$env(XML_LIBRARY)"
   }

   which, on Windows, sets the envariable to a default value, and then
   inserts, at the front, the directory where your main file is.

5. Limitations

   o  The "figure" element's "title" attribute is ignored.

   o  The "artwork" element's "name" and "type" attributes are ignored.

   o  The "artwork" element has a non-standard "src" attribute that is
      consulted only if slides are being generated, e.g.,

          <figure><artwork src="layers.gif" /></figure>

   o  The "xref" element's "pageno" attribute is ignored.

   o  The "references" elemeht has a non-standard "title" attribute,
      which can be used as an override.

References

   [1]  Rose, M., "Writing I-Ds and RFCs using XML", RFC 2629, June
        1999.

   [2]  <http://xml.resource.org/>

   [3]  <http://www.scriptics.com/software/tcltk/8.4.html>

   [4]  <http://www.zveno.com/zm.cgi/in-tclxml/>

   [5]  <rfc2629-author.html>





Rose                                                            [Page 6]

README                        xml2rfc v1.7                   August 2001


Author's Address

   Marshall T. Rose
   Invisible Worlds, Inc.
   131 Stony Circle
   Suite 500
   Santa Rosa, CA  95401
   US

   Phone: +1 707 578 2350
   EMail: mrose@invisible.net
   URI:   http://invisible.net/







































Rose                                                            [Page 7]

