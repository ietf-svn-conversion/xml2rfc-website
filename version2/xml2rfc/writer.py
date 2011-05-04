""" Writer classes to output rfc data to various formats """

import textwrap

def justify_inline(left_str, center_str, right_str, width=72):
    """ Takes three string arguments and outputs a single string with the 
        arguments left-justified, centered, and right-justified respectively.
        
        Throws an exception if the combined length of the three strings is 
        greater than the width.
    """

    if (len(left_str) + len(center_str) + len(right_str)) > width:
        raise Exception("The given strings are greater than a width of: "\
                                                            + str(width))
    else:
        str = left_str + ' '*((width/2)-len(center_str)/2-len(left_str)) \
          + center_str + ' '*((width/2)-len(center_str)/2-len(right_str)) \
          + right_str
        return str


class XmlRfcWriter:
    """ Base class for all writers """
    rfc = None

    def __init__(self, rfc):
        self.rfc = rfc
        
    def write(self, filename):
        raise NotImplementedError('write() must be overridden')


class RawTextRfcWriter(XmlRfcWriter):
    """ Writes to a text file, unpaginated, no headers or footers. """
    width = None
    
    def __init__(self, rfc):
        self.rfc = rfc
        self.width = 72
        self.buf = []
    
    def lb(self):
        """ Write a blank line to the file """
        self.buf.append('')

    def write_line(self, str, indent=0):
        """ Writes an (optionally) indented line preceded by a line break. """
        if len(str) > (self.width):
            raise Exception("The supplied line exceeds the page width!\n \
                                                                    " + str)
        self.lb()
        self.buf.append(' '*indent + str)
    
    def write_par(self, str, indent=0):
        """ Writes an indented and wrapped paragraph, preceded by a lb. """
        par = textwrap.wrap(str, self.width, \
                            initial_indent=' '*indent, \
                            subsequent_indent=' '*indent)
        self.lb()
        self.buf.extend(par)

    def write(self, filename):
        # Front page, left heading
        fp_left = [self.rfc.attribs['trad_header']]
        if 'number' in self.rfc.attribs:
            fp_left.append(self.rfc.attribs['number'])
        if 'updates' in self.rfc.attribs:
            fp_left.append(self.rfc.attribs['updates'])
        if 'obsoletes' in self.rfc.attribs:
            fp_left.append(self.rfc.attribs['obsoletes'])
        if 'category' in self.rfc.attribs:
            fp_left.append(self.rfc.attribs['category'])
        
        # Front page, right heading
        fp_right = []
        for author in self.rfc['front']['author']:
            fp_right.append(author.attribs['initials'] + ' ' + \
                            author.attribs['surname'])
            if 'organization' in author:
                fp_right.append(author['organization'].text)
        date = self.rfc['front']['date']
        fp_right.append(date.attribs['month'] + ' ' + date.attribs['year'])
        
        # Construct full heading
        for i in range(max(len(fp_left), len(fp_right))):
            if i < len(fp_left): left = fp_left[i]; 
            else: left = '';
            if i < len(fp_right): right = fp_right[i]; 
            else: right = '';
            self.buf.append(justify_inline(left, '', right))
        
        # Title, Status, Copyright, and Table of Contents
        self.write_line(self.rfc['front']['title'].text.center(self.width))
        self.write_line('Status of this Memo')
        self.write_par(self.rfc.attribs['status'], indent=3)
        self.write_line('Copyright Notice')
        self.write_par(self.rfc.attribs['copyright'], indent=3)
            
        # Write everything to file
        file = open(filename, 'w')
        for line in self.buf:
            file.write(line)
            file.write('\n')
 