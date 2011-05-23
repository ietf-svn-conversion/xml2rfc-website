#!/usr/bin/env python

from setuptools import setup

setup(name='xml2rfc',
    version='0.2',
    description='Validate and convert XML RFC documents to various output ' \
                  'formats',
    author='Concentric Sky',
    author_email='',
    url='',
    scripts=['scripts/xml2rfc'],
    packages=['xml2rfc', 'xml2rfc/writers'],
    package_data={'xml2rfc': [
                                'templates/*'
                                ]},
    install_requires=['lxml>=2.3'],
)
