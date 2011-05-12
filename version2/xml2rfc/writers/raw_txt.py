# Python libs
import textwrap
import string

# Local lib
from base import XmlRfcWriter
import tools


class RawTextRfcWriter(XmlRfcWriter):
    """ Writes to a text file, unpaginated, no headers or footers. """

    def __init__(self, xmlrfc, width=72):
        XmlRfcWriter.__init__(self, xmlrfc)
        self.width = width      # Page width
        self.buf = []           # Main buffer
        self.toc = []           # Table of contents buffer
        self.ref_index = 1      # Index number for the references section
        self.toc_marker = 0     # Line number in buffer to write toc too
        self.figure_count = 0
        self.table_count = 0

    def mark(self):
        """ Returns the current position in the buffer for post-processing """
        return len(self.buf)
        
    def lb(self, buf=None):
        """ Write a blank line to the file """
        if not buf:
            buf = self.buf
        buf.append('')

    def write_line(self, str, indent=0, lb=True, align='left', buf=None):
        """ Writes an (optionally) indented line preceded by a line break. """
        if not buf:
            buf = self.buf
        if len(str) > (self.width):
            raise Exception("The supplied line exceeds the page width!\n \
                                                                    " + str)
        if lb:
            self.lb(buf=buf)
        if align == 'left':
            buf.append(' ' * indent + str)
        elif align == 'center':
            buf.append(str.center(self.width))
        elif align == 'right':
            buf.append(str.rjust(self.width))

    def write_par(self, str, indent=0, sub_indent=None,bullet='', \
                  align='left', buf=None):
        """ Writes an indented and wrapped paragraph, preceded by a lb. """
        if not buf:
            buf = self.buf
        # We can take advantage of textwraps initial_indent by using a bullet
        # parameter and treating it separately.  We still need to indent it.
        initial = ' ' * indent + bullet
        if not sub_indent:
            # No sub_indent specified, use bullet length for indent amount
            subsequent = ' ' * len(initial)
        else:
            subsequent = ' ' * (sub_indent + indent)
        par = textwrap.wrap(str, self.width, \
                            initial_indent=initial, \
                            subsequent_indent=subsequent)
        self.lb()
        if align == 'left':
            buf.extend(par)
        if align == 'center':
            for line in par:
                buf.append(line.center(self.width))
        elif align == 'right':
            for line in par:
                buf.append(line.rjust(self.width))
    
    def write_raw(self, data, indent=0, align='left'):
        """ Writes a raw stream of characters, preserving space and breaks """
        # Append an indent to every newline of the data
        lines = data.split('\n')
        if align == 'center':
            # Find the longest line, and use that as a fixed center.
            longest_line = len(max(lines, key=len))
            indent_str = ' ' * ((self.width - longest_line) / 2)
            for line in lines:
                self.buf.append(indent_str + line)
        elif align == 'right':
            for line in lines:
                self.buf.append(line.rjust(self.width))
        else: # align == left
            indent_str = ' ' * indent
            for line in lines:
                self.buf.append(indent_str + line)
    
    def resolve_refs(self, element):
        """ Returns a string containing element text plus any inline refs """
        line = []
        if element.text:
            line.append(element.text)
        for child in element:
            if child.tag == 'xref':
                if child.text:
                    line.append(child.text + ' ')
                line.append('[' + child.attrib['target'] + ']')
                if child.tail:
                    line.append(child.tail)
            elif child.tag == 'eref':
                if child.text:
                    line.append(child.text + ' ')
                line.append('[' + child.attrib['target'] + ']')
                if child.tail:
                    line.append(child.tail)
            elif child.tag == 'iref': pass
        return ''.join(line)

    def write_section_rec(self, section, indexstring, appendix=False):
        """ Recursively writes <section> elements """
        if indexstring:
            # Prepend a neat index string to the title
            self.write_line(indexstring + ' ' + section.attrib['title'])
            # Write to TOC as well
            if section.attrib['toc'] != 'exclude':
                toc_indent = ' ' * ((indexstring.count('.') - 1) * 2)
                self.toc.append(toc_indent + indexstring + ' ' + \
                                section.attrib['title'])
        else:
            # Must be <middle> or <back> element -- no title or index.
            indexstring = ''
        
        for element in section:
            # Write elements in XML document order
            if element.tag == 't':
                self.write_t_rec(element)
            elif element.tag == 'figure':
                self.write_figure(element)
            elif element.tag == 'texttable':
                self.write_figure(element, table=True)
        
        index = 1
        for child_sec in section.findall('section'):
            if appendix == True:
                self.write_section_rec(child_sec, 'Appendix ' + \
                                       string.uppercase[index-1] + '.')
            else:
                self.write_section_rec(child_sec, indexstring + \
                                       str(index) + '.')
            index += 1

        # Set the ending index number so we know where to begin references
        if indexstring == '' and appendix == False:
            self.ref_index = index

    def write_figure(self, figure, table=False):
        """ Function that writes <figure> or <texttable> elements """
        figure_align = figure.attrib['align']
        preamble = figure.find('preamble')
        if preamble is not None:
            self.write_par(self.resolve_refs(preamble), indent=3, \
                           align=figure_align)
        if table:
            # <texttable> element
            self.table_count += 1
            lines = []
            headers = []
            align = figure.attrib['align']
            for column in figure.findall('ttcol'):
                headers.append(column.text)
            # Draw header
            borderstring = ['+']
            for header in headers:
                borderstring.append('-' * (len(header)+2))
                borderstring.append('+')
            self.write_line(''.join(borderstring), indent=3, lb=True, \
                            align=align)
            headerstring = ['|']
            for header in headers:
                headerstring.append(' ' + header + ' |')
            self.write_line(''.join(headerstring), indent=3, lb=False, \
                            align=align)
            self.write_line(''.join(borderstring), indent=3, lb=False, \
                            align=align)
            # Draw Cells
            cellstring = ['|']
            for i, cell in enumerate(figure.findall('c')):
                column = i % len(headers)
                celltext = ''
                if cell.text:
                    celltext = cell.text
                cellstring.append(celltext.center(len(headers[column])+2))
                cellstring.append('|')
                if column == len(headers) - 1:
                    # End of line
                    self.write_line(''.join(cellstring), indent=3, lb=False, \
                                    align=align)
                    cellstring = ['|']
                
            # Draw Bottom
            self.write_line(''.join(borderstring), indent=3, lb=False, \
                            align=align)
        else:
            # <artwork> element
            self.figure_count += 1
            # TODO: Needs to be aligned properly
            # Insert artwork text directly into the buffer
            artwork = figure.find('artwork')
            artwork_align = figure_align
            if 'align' in artwork.attrib:
                artwork_align = artwork.attrib['align']
            self.write_raw(figure.find('artwork').text, indent=3, \
                           align=artwork_align)
        
        postamble = figure.find('postamble')
        if postamble is not None:
            self.write_par(self.resolve_refs(postamble), indent=3, \
                           align=figure_align)
        
        # Write label
        if figure.attrib['title'] != '':
            title = ': ' + figure.attrib['title']
        else:
            title = ''
        if table:
            self.write_line('Table ' + str(self.table_count) + title, \
                            align='center')
        else:
            self.write_line('Figure ' + str(self.figure_count) + title, \
                            align='center')

    def write_t_rec(self, t, indent=3, sub_indent=None, bullet=''):
        """ Recursively writes <t> elements """
        line = []
        if t.text:
            line.append(t.text)

        for element in t:
            if element.tag == 'xref':
                if element.text:
                    line.append(element.text + ' ')
                line.append('[' + element.attrib['target'] + ']')
                if element.tail:
                    line.append(element.tail)
            elif element.tag == 'eref':
                if element.text:
                    line.append(element.text + ' ')
                line.append('[' + element.attrib['target'] + ']')
                if element.tail:
                    line.append(element.tail)
            elif element.tag == 'iref': pass
            elif element.tag == 'vspace':
                for i in range(int(element.attrib['blankLines'])):
                    line.append('\n')
                if element.tail:
                    line.append(element.tail)
            else:
                # Not an inline element.  Output what we have so far
                if len(line) > 0:
                    self.write_par(''.join(line), indent=indent, \
                                   sub_indent=sub_indent, bullet=bullet)
                    line = []
            
            if element.tag == 'list':
                # Default to the 'empty' list style -- 3 spaces
                bullet = '   '
                style = 'empty'
                hangIndent = None
                if 'style' in element.attrib:
                    style = element.attrib['style']
                if style == 'symbols':
                    bullet = 'o  '
                for i, t in enumerate(element.findall('t')):
                    if style == 'numbers':
                        bullet = str(i + 1) + '.  '
                    elif style == 'letters':
                        bullet = string.ascii_lowercase[i % 26] + '.  '
                    elif style == 'hanging':
                        bullet = t.attrib['hangText'] + ' '
                        hangIndent = element.attrib['hangIndent']
                    if hangIndent:
                        self.write_t_rec(t, indent=indent, bullet=bullet, \
                                         sub_indent=int(hangIndent))
                    else:
                        # Empty
                        self.write_t_rec(t, indent=indent, bullet=bullet)
                if element.tail:
                    self.write_par(element.tail, indent=3)

            elif element.tag == 'figure':
                self.write_figure(element)
                if element.tail:
                    self.write_par(element.tail, indent=3)
            elif element.tag == 'texttable':
                self.write_figure(element, table=True)
                if element.tail:
                    self.write_par(element.tail, indent=3)

        if len(line) > 0:
            self.write_par(''.join(line), indent=indent, bullet=bullet, \
                           sub_indent=sub_indent)

    def write_reference_list(self, references):
        """ Writes a formatted list of <reference> elements """
        # Use very first reference's [bullet] length for indent amount
        sub_indent = len(references.find('reference').attrib['anchor']) + 4
        # [surname, initial.,] "title", (STD), (BCP), (RFC), (Month) Year.
        for i, ref in enumerate(references.findall('reference')):
            refstring = []
            authors = ref.findall('front/author')
            for j, author in enumerate(authors):
                organization = author.find('organization')
                if organization is not None and organization.text is not None:
                    refstring.append(organization.text + ', ')
                else:
                    refstring.append(author.attrib['surname'] + ', ' + \
                                     author.attrib['initials'] + ', ')
                    if j == len(authors) - 2:
                        # Second-to-last, add an "and"
                        refstring.append('and ')
                        refstring.append(author.attrib['surname'] + ', ' + \
                                         author.attrib['initials'] + '., ')
            refstring.append('"' + ref.find('front/title').text + '", ')
            # TODO: Handle seriesInfo
            date = ref.find('front/date')
            if 'month' in date.attrib:
                refstring.append(date.attrib['month'])
            refstring.append(date.attrib['year'] + '.')
            # TODO: Should reference list have [anchor] or [1] for bullets?
            bullet = '[' + ref.attrib['anchor'] + ']  '
            self.write_par(''.join(refstring), indent=3, bullet=bullet, \
                           sub_indent=sub_indent)
    
    def post_write_toc(self):
        """ Writes the table of contents to temporary buffer and returns
            
            This should only be called after the initial buffer is written.
        """
        tmpbuf = ['']
        self.write_line("Table of Contents", buf=tmpbuf)
        self.lb(buf=tmpbuf)
        for line in self.toc:
            self.write_line(line, indent=3, lb=False, buf=tmpbuf)
        return tmpbuf

    def write_buffer(self):
        """ Internal method that writes the entire RFC tree to a buffer

            Actual writing to a file, plus some post formatting is handled
            in self.write(), which is the public method to be called.
        """
        # Prepare front page left heading
        fp_left = [self.r.attrib['trad_header']]
        if 'number' in self.r.attrib:
            fp_left.append('Request for Comments: ' + self.r.attrib['number'])
        else:
            # No RFC number -- assume internet draft
            fp_left.append('Internet-Draft')
        if 'updates' in self.r.attrib:
            if self.r.attrib['updates'] != '':
                fp_left.append(self.r.attrib['updates'])
        if 'obsoletes' in self.r.attrib:
            if self.r.attrib['obsoletes'] != '':
                fp_left.append(self.r.attrib['obsoletes'])
        if 'category' in self.r.attrib:
            fp_left.append('Category: ' + self.r.attrib['category'])

        # Prepare front page right heading
        fp_right = []
        for author in self.r.findall('front/author'):
            fp_right.append(author.attrib['initials'] + ' ' + \
                            author.attrib['surname'])
            organization = author.find('organization')
            if organization is not None:
                if 'abbrev' in organization.attrib:
                    fp_right.append(organization.attrib['abbrev'])
                else:  
                    fp_right.append(organization.text)
        date = self.r.find('front/date')
        month = ''
        if 'month' in date.attrib:
            month = date.attrib['month']
        fp_right.append(month + ' ' + date.attrib['year'])

        # Front page heading
        for i in range(max(len(fp_left), len(fp_right))):
            if i < len(fp_left):
                left = fp_left[i]
            else:
                left = ''
            if i < len(fp_right):
                right = fp_right[i]
            else:
                right = ''
            self.buf.append(tools.justify_inline(left, '', right))

        # Title & Optional docname
        self.write_line(self.r.find('front/title').text.center(self.width))
        if 'docName' in self.r.attrib:
            self.write_line(self.r.attrib['docName'].center(self.width), \
                            lb=False)

        # Abstract
        abstract = self.r.find('front/abstract')
        if abstract is not None:
            self.write_line('Abstract')
            for t in abstract.findall('t'):
                self.write_t_rec(t)

        # Status
        self.write_line('Status of this Memo')
        self.write_par(self.r.attrib['status'], indent=3)

        # Copyright
        self.write_line('Copyright Notice')
        self.write_par(self.r.attrib['copyright'], indent=3)
        
        # Mark table of contents to be post-written
        self.toc_marker = self.mark()
        
        # Middle sections
        self.write_section_rec(self.r.find('middle'), None)

        # References section
        ref_indexstring = str(self.ref_index) + '.'
        ref_title = ref_indexstring + ' References'
        self.write_line(ref_title)
        self.toc.append(ref_title)
        # Treat references as nested only if there is more than one <references>
        references = self.r.findall('back/references')
        if len(references) > 1:
            for index, reference_list in enumerate(references):
                ref_title = ref_indexstring + str(index + 1) + '. ' + \
                            reference_list.attrib['title']
                self.write_line(ref_title)
                toc_indent = ' ' * ((ref_title.count('.') - 1) * 2)
                self.toc.append(toc_indent + ref_title)
                self.write_reference_list(reference_list)
        else:
            self.write_reference_list(references[0])
        
        # Appendix sections
        self.write_section_rec(self.r.find('back'), None, appendix=True)

        # Authors address section
        authors = self.r.findall('front/author')
        if len(authors) > 1:
            self.write_line("Authors' Addresses")
            self.toc.append("Authors' Addresses")
        else:
            self.write_line("Authors Address")
            self.toc.append("Authors Address")
        for author in authors:
            if 'role' in author.attrib:
                self.write_line(author.attrib['fullname'] + ', ' + \
                                author.attrib['role'], indent=3)
            else:
                self.write_line(author.attrib['fullname'], indent=3)
            organization = author.find('organization')
            if organization is not None:
                self.write_line(organization.text, indent=3, lb=False)
            address = author.find('address')
            if address is not None:
                postal = address.find('postal')
                if postal is not None:
                    for street in postal.findall('street'):
                        if street.text:
                            self.write_line(street.text, indent=3, lb=False)
                    cityline = []
                    city = postal.find('city')
                    if city is not None:
                        cityline.append(city.text)
                        cityline.append(', ')
                    region = postal.find('region')
                    if region is not None:
                        cityline.append(region.text)
                        cityline.append(' ')
                    code = postal.find('code')
                    if code is not None:
                        cityline.append(code.text)
                    self.write_line(''.join(cityline), indent=3, lb=False)
                    country = postal.find('country')
                    if country is not None:
                        self.write_line(country.text, indent=3, lb=False)
                self.lb()
                phone = address.find('phone')
                if phone is not None:
                    self.write_line('Phone: ' + phone.text, indent=3, lb=False)
                fascimile = address.find('fascimile')
                if fascimile is not None:
                    self.write_line('Fax:   ' + fascimile.text, indent=3, lb=False)
                email = address.find('email')
                if email is not None:
                    self.write_line('EMail: ' + email.text, indent=3, lb=False)
                uri = address.find('uri')
                if uri is not None:
                    self.write_line('URI:   ' + uri.text, indent=3, lb=False)
            self.lb()

        # EOF

    def write(self, filename):
        """ Public method to write rfc document to a file """

        # Write RFC to buffer
        self.write_buffer()

        # Write buffer to file
        file = open(filename, 'w')
        for line_num, line in enumerate(self.buf):
            # Check for marks
            if line_num == self.toc_marker:
                # Write TOC
                tmpbuf = self.post_write_toc()
                for tmpline in tmpbuf:
                    file.write(tmpline)
                    file.write('\r\n')
            file.write(line)
            file.write('\r\n')
        file.close()
