package XML::Saxon::XSLT2;

use 5.008;
use common::sense;
use Carp;
use Scalar::Util qw[blessed];
use IO::Handle;

our $VERSION = '0.001';
my $classpath;

BEGIN
{
	foreach my $path (qw(/usr/share/java/saxon9he.jar /usr/local/share/java/saxon9he.jar))
	{
		$classpath = $path if -e $path;
	}
}

use Inline Java => 'DATA', CLASSPATH=>$classpath;

sub new
{
	my ($class, $xslt) = @_;
	$xslt = $class->_xml($xslt);
	return bless { 'transformer' => XML::Saxon::XSLT2::Transformer->new($xslt) }, $class;
}

sub transform
{
	my ($self, $doc, $type) = @_;
	$type ||= 'xml';
	$doc = $self->_xml($doc);
	return $self->{'transformer'}->transform($doc, $type);
}

sub transform_document
{
	my $self = shift;
	my $r    = $self->transform(@_);
	
	$self->{'parser'} ||= XML::LibXML->new;
	return $self->{'parser'}->parse_string($r);
}

sub _xml
{
	my ($proto, $xml) = @_;
	
	if (blessed($xml) && $xml->isa('XML::LibXML::Document'))
	{
		return $xml->toString;
	}
	elsif (blessed($xml) && $xml->isa('IO::Handle'))
	{
		local $/;
		my $str = <$xml>;
		return $str;
	}
	elsif (ref $xml eq 'GLOB')
	{
		local $/;
		my $str = <$xml>;
		return $str;
	}
	
	return $xml;
}

sub parameters
{
	my ($self, %params) = @_;
	$self->{'transformer'}->paramClear();
	while (my ($k,$v) = each %params)
	{
		if (ref $v eq 'ARRAY')
		{
			(my $type, $v) = @$v;
			my $func = 'paramAdd' . {
				double    => 'Double',
				string    => 'String',
				long      => 'Long',
				'int'     => 'Long',
				integer   => 'Long',
				decimal   => 'Decimal',
				float     => 'Float',
				boolean   => 'Boolean',
				bool      => 'Boolean',
				qname     => 'QName',
				uri       => 'URI',
				date      => 'Date',
				datetime  => 'DateTime',
				}->{lc $type};
			croak "$type is not a supported type"
				if $func eq 'paramAdd';
			$self->{'transformer'}->$func($k, $v);
		}
		elsif (blessed($v) && $v->isa('DateTime'))
		{
			$self->{'transformer'}->paramAddDateTime($k, "$v");
		}	
		elsif (blessed($v) && $v->isa('Math::BigInt'))
		{
			$self->{'transformer'}->paramAddLong($k, $v->bstr);
		}
		elsif (blessed($v) && $v->isa('URI'))
		{
			$self->{'transformer'}->paramAddURI($k, "$v");
		}	
		else
		{
			$self->{'transformer'}->paramAddString($k, "$v");
		}
	}
	return $self;
}

1;

=head1 NAME

XML::Saxon::XSLT2 - process XSLT 2.0 using Saxon 9.x.

=head1 SYNOPSIS

 my $trans  = XML::Saxon::XSLT2->new( $xslt );
 my $output = $trans->transform($input);

=head1 DESCRIPTION

This module implements XSLT 1.0 and 2.0 using Saxon 9.x via L<Inline::Java>.

It expects Saxon to be installed in either '/usr/share/java/saxon9he.jar'
or '/usr/local/share/java/saxon9he.jar'. Future versions should be more
flexible. The saxon9he.jar file can be found at L<http://saxon.sourceforge.net/> -
just dowload the latest Java release of Saxon-HE 9.x, open the Zip archive,
extract saxon9he.jar and save it to one of the two directories above.

=head2 Constructor

=over 4

=item C<< XML::Saxon::XSLT2->new($xslt) >>

Creates a new transformation. $xslt may be a string, a file handle or an
L<XML::LibXML::Document>.

=back

=head2 Methods

=over 4

=item C<< $trans->parameters($key=>$value, $key2=>$value2, ...) >>

Sets transformation parameters prior to running the transformation.

Each key is a parameter name.

Each value is the parameter value. This may be a scalar, in which case
it's treated as an xs:string; a L<DateTime> object, which is treated as
an xs:dateTime; a L<URI> object, xs:anyURI; a L<Math::BigInt>, xs:long;
or an arrayref where the first element is the type and the second the
value. For example:

 $trans->parameters(
    now           => DateTime->now,
    madrid_is_capital_of_spain => [ boolean => 1 ],
    price_of_fish => [ decimal => '1.99' ],
    my_link       => URI->new('http://example.com/'),
    your_link     => [ uri => 'http://example.net/' ],
    );

The following types are supported via the arrayref notation: float, double,
long (alias int, integer), decimal, bool (alias boolean), string, qname, uri,
date, datetime. These are case-insensitive.

=item C<< $trans->transform($doc, $type) >>

Run a transformation, returning the output as a string.

$doc may be a string, a file handle or an L<XML::LibXML::Document>.

$type may be 'xml', 'xhtml', 'html' or 'text' to set the output mode. 'xml' is
the default.

=item C<< $trans->transform_document($doc, $type) >>

Run a transformation, returning the output as an L<XML::LibXML::Document>.

$doc may be a string, a file handle or an L<XML::LibXML::Document>.

$type may be 'xml', 'xhtml', 'html' or 'text' to set the output mode. 'xml' is
the default.

This method is slower than C<transform>.

=back

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

Known limitations:

=over 4

=item * B<xsl:message>

Saxon outputs messages written via E<lt>xsl:messageE<gt> to STDERR. There
doesn't seem to be any way to capture and return these messages (not even using
L<Capture::Tiny> or its ilk).

=back

=head1 SEE ALSO

C<XML::LibXSLT> is probably more reliable, and allows you to define your
own XSLT extension functions. However, the libxslt library that it's based
on only supports XSLT 1.0.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2010 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

__DATA__
__Java__
import net.sf.saxon.s9api.*;
import org.xml.sax.Attributes;
import org.xml.sax.ContentHandler;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.helpers.XMLFilterImpl;
import org.w3c.dom.Document;
import org.xml.sax.Attributes;
import org.xml.sax.ContentHandler;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.helpers.XMLFilterImpl;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.ErrorListener;
import javax.xml.transform.SourceLocator;
import javax.xml.transform.TransformerException;
import javax.xml.transform.sax.SAXSource;
import javax.xml.transform.stream.StreamSource;
import java.io.*;
import java.math.BigDecimal;
import java.net.URI;
import java.util.*;

public class Transformer
{
	private XsltExecutable xslt;
	private Processor proc;
	private HashMap<String, XdmAtomicValue> params;

	public Transformer (String stylesheet)
		throws SaxonApiException
	{
		proc = new Processor(false);
		XsltCompiler comp = proc.newXsltCompiler();
		xslt = comp.compile(new StreamSource(new StringReader(stylesheet)));
		params = new HashMap<String, XdmAtomicValue>();
	}
	
	public void paramAddString (String key, String value)
	{
		params.put(key, new XdmAtomicValue(value));
	}

	public void paramAddLong (String key, long value)
	{
		params.put(key, new XdmAtomicValue(value));
	}

	public void paramAddDecimal (String key, BigDecimal value)
	{
		params.put(key, new XdmAtomicValue(value));
	}

	public void paramAddFloat (String key, float value)
	{
		params.put(key, new XdmAtomicValue(value));
	}

	public void paramAddDouble (String key, double value)
	{
		params.put(key, new XdmAtomicValue(value));
	}

	public void paramAddBoolean (String key, boolean value)
	{
		params.put(key, new XdmAtomicValue(value));
	}

	public void paramAddURI (String key, String value)
		throws java.net.URISyntaxException
	{
		params.put(key, new XdmAtomicValue(new URI(value.toString())));
	}

	public void paramAddQName (String key, String value)
	{
		params.put(key, new XdmAtomicValue(new QName(value.toString())));
	}

	public void paramAddDate (String key, String value)
		throws SaxonApiException
	{
		ItemTypeFactory itf = new ItemTypeFactory(proc);
		ItemType dateType = itf.getAtomicType(new QName("http://www.w3.org/2001/XMLSchema", "date"));
		params.put(key, new XdmAtomicValue(value, dateType));
	}

	public void paramAddDateTime (String key, String value)
		throws SaxonApiException
	{
		ItemTypeFactory itf = new ItemTypeFactory(proc);
		ItemType dateTimeType = itf.getAtomicType(new QName("http://www.w3.org/2001/XMLSchema", "datetime"));
		params.put(key, new XdmAtomicValue(value, dateTimeType));
	}

	public XdmAtomicValue paramGet (String key)
	{
		return params.get(key);
	}

	public void paramRemove (String key)
	{
		params.remove(key);
	}
	
	public void paramClear ()
	{
		params.clear();
	}

	public String transform (String doc, String method)
		throws SaxonApiException
	{
		XdmNode source = proc.newDocumentBuilder().build(
			new StreamSource(new StringReader(doc))
			);

		XsltTransformer trans = xslt.load();
		trans.setInitialContextNode(source);

		Serializer out = new Serializer();
		out.setOutputProperty(Serializer.Property.METHOD, method);
		StringWriter sw = new StringWriter();
		out.setOutputWriter(sw);
		trans.setDestination(out);
		
		Iterator i = params.keySet().iterator();
		while (i.hasNext())
		{
			Object k = i.next();
			XdmAtomicValue v = params.get(k);
			
			trans.setParameter(new QName(k.toString()), v);
		}

		trans.transform();
		
		return sw.toString();
	}
}
