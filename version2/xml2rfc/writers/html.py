# External libs
from lxml.builder import E
import lxml.etree

# Local libs
from raw_txt import RawTextRfcWriter

# HTML Specific Defaults that are not provided in XML document
# TODO: This could possibly go in parser.py, as a few defaults already do.
defaults =  {'doctype': '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN">',
             'style_title':  'Xml2Rfc (sans serif)',
            }

class HtmlRfcWriter(RawTextRfcWriter):
    """ Writes to an HTML with embedded CSS """

    def __init__(self, xmlrfc, css_document='templates/rfc.css',
                 expanded_css=True, lang='en'):
        RawTextRfcWriter.__init__(self, xmlrfc)
        self.html = E.html(lang=lang)
        self.css_document = css_document
        self.expanded_css = expanded_css
        
        # Create head element, add style/metadata/etc information
        self.html.append(self._build_head())
        
        # Create body element -- everything will be added to this
        self.body = E.body()
        self.html.append(self.body)
        
    def _build_stylesheet(self):
        """ Returns either a <link> or <style> element for css data.
        
            The element returned is dependent on the value of expanded_css
        """
        if self.expanded_css:
            file = open(self.css_document, 'r')
            element = E.style(file.read(), title=defaults['style_title'])
        else:
            element = E.link(rel='stylesheet', href=self.css_document)
        element.attrib['type'] = 'text/css'
        return element
    
    def _build_head(self):
        """ Returns the constructed <head> element """
        head = E.head()
        head.append(self._build_stylesheet())
        return head

    # -----------------------------------------
    # Base writer interface methods to override
    # -----------------------------------------
    
    def mark_toc(self):
        pass
    
    def write_raw(self, text, align='left'):
        pass
        
    def write_label(self, text, align='center'):
        pass
    
    def write_title(self, title, docName=None):
        p = E.p(title)
        p.attrib['class'] = 'title'
        if docName:
            p.append(E.br())
            span = E.span(docName)
            span.attrib['class'] = 'filename'
            p.append(span)
        self.body.append(p)
        
    def write_heading(self, text, bullet=None, idstring=None, anchor=None):
        h1 = E.h1()
        if idstring:
            h1.attrib['id'] = idstring
        if bullet:
            # Use separate elements for bullet and text
            a_bullet = E.a(bullet)
            if idstring:
                a_bullet.attrib['href'] = '#' + idstring
            h1.append(a_bullet)
            if anchor:
                # Use an anchor link for heading
                a_text = E.a(text)
                a_text.attrib['href'] = '#' + anchor
                h1.append(a_text)
            else:
                # Plain text
                a_bullet.tail = ' ' + text
        else:
            # Only use one <a> pointing to idstring
            a = E.a(text)
            if idstring:
                a.attrib['href'] = '#' + idstring
            h1.append(a)
        self.body.append(h1)

    def write_paragraph(self, text, align='left', idstring=None):
        if text:
            p = E.p(text)
            self.body.append(p)

    def write_list(self, list):
        pass
    
    def write_top(self, left_header, right_header):
        """ Adds the header table """
        table = E.table()
        table.attrib['class'] = 'header'
        tbody = E.tbody()
        for i in range(max(len(left_header), len(right_header))):
            if i < len(left_header):
                left_string = left_header[i]
            else:
                left_string = ''
            if i < len(right_header):
                right_string = right_header[i]
            else:
                right_string = ''
            td_left = E.td(left_string)
            td_left.attrib['class'] = 'left'
            td_right = E.td(right_string)
            td_right.attrib['class'] = 'right'
            tbody.append(E.tr(td_left, td_right))
        table.append(tbody)
        self.body.append(table)
    
    def write_address_card(self, author):
        pass
    
    def write_reference_list(self, list):
        pass
    
    def draw_table(self, table):
        pass
    
    def expand_refs(self, element):
        """ Returns a <p> element with inline references expanded properly """
        return element.text

    def add_to_toc(self, bullet, title, anchor=None):
        pass
    
    def write_to_file(self, filename):
        # Write the tree to the file
        file = open(filename, 'w')
        file.write(defaults['doctype'] + '\n')
        file.write(lxml.etree.tostring(self.html, pretty_print=True))
