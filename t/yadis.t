#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 34;

use Net::Yadis;

warn "This test depends on the consistency of http://smoker.myopenid.com/ and http://netmesh.info/jernst\n";

my ($yadis, $svc, $svb, @services, @types, @uris);

eval {$yadis = Net::Yadis::discover('http://smoker.myopenid.com/');};
isa_ok($yadis, "Net::Yadis", "Discover http://smoker.myopenid.com/")
    or diag($@);
@services = $yadis->services;
is(@services, 1, "Smoker has just one service");
$svc = $services[0];
ok($svc->is_type("^http://openid.net/signon/"), "Smoker's service is OpenID");

@types = $svc->types;
is(@types, 1, "Smoker's service has one type.");
is($types[0], "http://openid.net/signon/1.0", 
                    "Smoker's service is of type OpenID 1.0");
                    
is($svc->uri, "http://www.myopenid.com/server", "Smoker's OpenID server");
is($svc->uri, undef, "Smoker has but one OpenID server URI");

@uris = $svc->uris;
is($uris[0], "http://www.myopenid.com/server", 
                "Smoker's OpenID server (alternate method)");
                
is($svc->findTag("Delegate", 'http://openid.net/xmlns/1.0'),
    "http://smoker.myopenid.com/", "Smoker's OpenID Delegate URL");

is($yadis->service_of_type("^http://openid.net/signon/"), $svc,
            "Smoker's service of type OpenID");

is($yadis->service_of_type("^http://openid.net/signon/"), undef,
            "Smoker's second service of type OpenID is undefined");

eval{$yadis = Net::Yadis::discover('http://netmesh.info/jernst');};
isa_ok($yadis, "Net::Yadis", "Discover http://netmesh.info/jernst")
    or diag($@);

@services = $yadis->services;
is(@services, 7, "Johannes has 7 services");

$svc = $yadis->service_of_type("^http://lid.netmesh.org/sso");
ok($svc->is_type("http://lid.netmesh.org/sso/2.0b5"), 
                        "Johannes has LID sso 2.0b5");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/sso");
is($svc, undef, "Johannes has just one LID sso service");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/2");
ok($svc->is_type("http://lid.netmesh.org/2.0b5"), 
                        "Johannes has LID 2.0b5");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/post/r");
ok($svc->is_type("http://lid.netmesh.org/post/receiver/2.0b5"), 
                        "Johannes has LID post reciever 2.0b5");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/format");
ok($svc->is_type("http://lid.netmesh.org/format-negotiation/2.0b5"), 
                        "Johannes has LID format negotiation 2.0b5");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/trav");
ok($svc->is_type("http://lid.netmesh.org/traversal/2.0b5"), 
                        "Johannes has LID traversal 2.0b5");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/post/s");
ok($svc->is_type("http://lid.netmesh.org/post/sender/2.0b5"), 
                        "Johannes has LID post sender 2.0b5");
$svc = $yadis->service_of_type("^http://lid.netmesh.org/rely");
ok($svc->is_type("http://lid.netmesh.org/relying-party/2.0b5"), 
                        "Johannes has LID relying party 2.0b5");


# test prioritizing and getting attributes of tags in the service
my $xrds_xml = '<?xml version="1.0" encoding="UTF-8"?>
<xrds:XRDS
    xmlns:xrds="xri://$xrds"
    xmlns="xri://$xrd*($v*2.0)"
    xmlns:openid="http://openid.net/xmlns/1.0">
  <XRD>

    <Service priority="10">
      <Type>http://openid.net/signon/1.0</Type>
      <URI>http://www.myopenid.com/servir</URI>
      <URI priority="57">http://www.myopenid.com/servor</URI>
      <URI priority="64">http://www.myopenid.com/server</URI>
      <openid:Delegate>http://frank.livejournal.com/</openid:Delegate>
      <junk>Ton Cents</junk>
    </Service>

    <Service priority="5">
      <Type>http://openid.net/signon/1.0</Type>
      <URI>http://www.myclosedid.com/servir</URI>
      <URI priority="57">http://www.myclosedid.com/servor</URI>
      <URI priority="64">http://www.myclosedid.com/server</URI>
      <openid:Delegate>http://frank.livejournal.com/</openid:Delegate>
      <junk>Con Tents</junk>
    </Service>

  </XRD>
</xrds:XRDS>
';

eval{
    $yadis = Net::Yadis->new("http://foobar.voodoo.com/", 
                             "http://foobar.voodoo.com/xrds",
                             $xrds_xml);
    };
isa_ok($yadis, "Net::Yadis", "New from foodoo voobar example")
    or diag($@);

$svc = $yadis->service_of_type("^http://openid.net/signon/");
is($svc->uri, "http://www.myclosedid.com/servor", "foobar.voodoo.com svc 1 URI 1");
is($svc->uri, "http://www.myclosedid.com/server", "foobar.voodoo.com svc 1 URI 2");
is($svc->uri, "http://www.myclosedid.com/servir", "foobar.voodoo.com svc 1 URI 3");
is($svc->uri, undef, "foobar.voodoo.com svc1 has 3 URIs");
my ($contents, $attrs) = $svc->findTag("junk");
is($contents, "Con Tents", "foobar.voodoo.com svc 1 findTag junk contents");
is($svc->getAttribute("priority"), "5", "svc->getAttribute works");

$svc = $yadis->service_of_type("^http://openid.net/signon/");
is($svc->uri, "http://www.myopenid.com/servor", "foobar.voodoo.com svc 2 URI 1");
is($svc->uri, "http://www.myopenid.com/server", "foobar.voodoo.com svc 2 URI 2");
is($svc->uri, "http://www.myopenid.com/servir", "foobar.voodoo.com svc 2 URI 3");
is($svc->uri, undef, "foobar.voodoo.com svc 2 has 3 URIs");
my ($contents, $attrs) = $svc->findTag("junk");
is($contents, "Ton Cents", "foobar.voodoo.com svc 2 findTag junk contents");
is($svc->getAttribute("priority"), "10", "svc->getAttribute still works");

