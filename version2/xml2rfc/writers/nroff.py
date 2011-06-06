# --------------------------------------------------
# Copyright The IETF Trust 2011, All Rights Reserved
# --------------------------------------------------

# Local libs
from xml2rfc.writers.paginated_txt import PaginatedTextRfcWriter
from xml2rfc.writers.raw_txt import RawTextRfcWriter
from compiler.pyassem import RAW
import textwrap


class NroffRfcWriter(PaginatedTextRfcWriter):
    """ Writes to an nroff formatted file 
        
        The page width is controlled by the *width* parameter.
    """

    default_header = ['.pl 10.0i',      # Page length
                      '.po 0',          # Page offset
                      '.ll 7.2i',       # Line length
                      '.lt 7.2i',       # Title length
                      '.nr LL 7.2i',    # Printer line length
                      '.nr LT 7.2i',    # Printer title length
                      '.hy 0',          # Disable hyphenation
                      '.ad l',          # Left margin adjustment only
                      ]

    def __init__(self, xmlrfc, width=72, quiet=False, verbose=False):
        PaginatedTextRfcWriter.__init__(self, xmlrfc, width=width, \
                                        quiet=quiet, verbose=verbose)
        self.curr_indent = 0    # Used like a state machine to control
                                # whether or not we print a .in command
    
    def _indent(self, amount):
        # Writes an indent command if it differs from the last
        if amount != self.curr_indent:
            self._write_line('.in ' + str(amount))
            self.curr_indent = amount
        
    def _write_line(self, string):
        # Used by nroff to write a line with no nroff commands
        self.buf.append(string)

    def _write_text(self, string, indent=0, sub_indent=None, bullet='', \
                  align='left', lb=False, buf=None, strip=True):
        #-------------------------------------------------------------
        # RawTextRfcWriter override
        #
        # We should be able to handle mostly all of the nroff commands by
        # intercepting the alignment and indentation arguments
        #-------------------------------------------------------------
        if not buf:
            buf = self.buf
            
        # Store buffer position for paging information
        begin = len(self.buf)

        if lb:
            self._lb(buf=buf)
        if string:
            if strip:
                # Strip initial whitespace
                string = string.lstrip()
            if bullet:
                string = bullet + string
            par = textwrap.wrap(string, self.width)
            # TODO: Nroff alignment
            # Create nroff commands based on bullet & alignment
            if len(bullet) > 0:
                if sub_indent:
                    full_indent = indent + sub_indent
                else:
                    full_indent = indent + len(bullet)
                self._indent(full_indent)
                self._write_line('.ti ' + str(indent))
            else:
                self._indent(indent)
            buf.extend(par)
        
        # Page break information   
        end = len(self.buf)
        self.section_marks[begin] = end - begin

        """
        elif bullet:
            # If the string is empty but a bullet was declared, just
            # print the bullet
            buf.append(initial)
        """
        
    def _post_write_toc(self, tmpbuf):
        # Wrap a nofill/fill block around TOC
        tmpbuf.append('.ti 0')
        tmpbuf.append('Table of Contents')
        tmpbuf.append('')
        tmpbuf.append('.in 3')
        tmpbuf.append('.nf')
        tmpbuf.extend(self.toc)
        tmpbuf.append('.fi')
        return tmpbuf

    # ---------------------------------------------------------
    # PaginatedTextRfcWriter overrides
    # ---------------------------------------------------------

    def write_title(self, text, docName=None):
        # Override to use .ti commands
        self._lb()
        if docName:
            self._write_line('.ce 2')
            self._write_line(text)
            self._write_line(docName)
        else:
            self._write_line('.ce 1')
            self._write_line(text)

    def write_raw(self, text, indent=3, align='left', blanklines=0):
        # Wrap in a no fill block
        self._indent(indent)
        self._write_line('.nf')
        PaginatedTextRfcWriter.write_raw(self, text, indent=0, align=align, \
                                         blanklines=blanklines)
        self._write_line('.fi')

    def write_heading(self, text, bullet='', idstring=None, anchor=None, \
                      level=1):
        # Override to use a .ti command
        self._lb()
        if bullet:
            bullet += '  '
        self._write_line('.ti 0')
        self._write_line(bullet + text)

    def pre_processing(self):
        """ Inserts an nroff header into the buffer """

        # Construct the RFC header and footer
        PaginatedTextRfcWriter.pre_processing(self)

        # Insert the standard nroff settings
        self.buf.extend(NroffRfcWriter.default_header)

        # Insert the RFC header and footer information
        self._write_line('.ds LH ' + self.left_header)
        self._write_line('.ds CH ' + self.center_header)
        self._write_line('.ds RH ' + self.right_header)
        self._write_line('.ds LF ' + self.left_footer)
        self._write_line('.ds CF ' + self.center_footer)
        self._write_line('.ds RF FORMFEED[Page] % ')
    
    def post_processing(self):
        """ Insert page break commands """

        # Write buffer to secondary buffer, inserting breaks every 58 lines
        page_len = 0
        page_maxlen = 55
        for line_num, line in enumerate(self.buf):
            if line_num in self.section_marks:
                # If this section will exceed a page, insert a break command
                if page_len + self.section_marks[line_num] > page_maxlen:
                    self.paged_buf.append('.bp')
                    page_len = 0
            if page_len + 1 > 55:
                self.paged_buf.append('.bp')
                page_len = 0
            self.paged_buf.append(line)
            page_len += 1

    def write_to_file(self, filename):
        PaginatedTextRfcWriter.write_to_file(self, filename)
