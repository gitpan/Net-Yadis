#!/usr/bin/perl
# Copyright 2006 JanRain Inc.  Licensed under LGPL

package Net::Yadis;

use warnings;
use strict;

$VERSION = "0.7"

eval "use LWPx::ParanoidAgent;";
if($@) {
    warn "consider installing more secure LWPx::ParanoidAgent\n";
    use LWP::UserAgent;
};
use XML::XPath;

# finds meta http-equiv tags
use Net::Yadis::HTMLParse qw(parseMetaTags);

# must be lowercase
my $YADIS_HEADER = 'x-yadis-location';

# constructor applying the Yadis discovery protocol on a URI
# Should be called in an eval block; it dies on errors
sub discover {
    my $uri = shift;

    my $ua = LWP::UserAgent->new;
    my $resp = $ua->get($uri, 'Accept' => 'application/xrds+xml');

    die "Failed to fetch $uri" unless $resp->is_success;
    my ($xrds_text, $xrds_uri);
    my $ct = $resp->header('content-type');
    if ($ct eq 'application/xrds+xml') {
        $xrds_text = $resp->content;
        $xrds_uri = $resp->base;
    }
    else {
        my $yadloc = $resp->header($YADIS_HEADER);
        
        unless($yadloc) {
            my $equiv_headers = parseMetaTags($resp->content);
            $yadloc = $equiv_headers->{$YADIS_HEADER};
        }
        if($yadloc) {
            my $resp2 = $ua->get($yadloc);
            die "Bad Yadis URL: $uri ; Could not fetch $yadloc"
                unless $resp2->is_success; 
            $xrds_text = $resp2->content;
            $xrds_uri = $resp2->base; # but out of spec if not equal to $yadloc
        }
        else {
            die "$uri is not a YADIS URL";
        }
    }
    Net::Yadis->new($uri, $xrds_uri, $xrds_text)
}

# $yadis_url : the identity URL
# $xrds_url : where we got the xrds document
# $xml : the xml as text
sub new {
    my $caller = shift;
    my ($yadis_url, $xrds_url, $xml) = @_;

    my $class = ref($caller) || $caller;

    my $xrds;
    eval{$xrds = XML::XPath->new(xml => $xml)};
    if ($@) {
        warn $@;
        return undef;
    }
    $xrds->set_namespace("xrds", 'xri://$xrds');
    $xrds->set_namespace("xrd", 'xri://$xrd*($v*2.0)');

    my $self = {
        yadis_url     => $yadis_url,
        xrds_url => $xrds_url,
        xrds    => $xrds,
        xml     => $xml,
        };

    bless ($self, $class);
}

sub xml {
    my $self = shift;
    $self->{xml};
}
sub url {
    my $self = shift;
    $self->{yadis_url};
}
sub xrds_url {
    my $self = shift;
    $self->{xrds_url};
}
sub xrds_xpath {
    my $self = shift;
    $self->{xrds};
}

# sorting helper function for xpath nodes
# I wonder if doing the random order for the services significantly
# increases the running time of this function.
sub byPriority {
    my $apriori = $a->getAttribute('priority');
    my $bpriori = $b->getAttribute('priority');
    srand;
    # a defined priority comes before an undefined priority.
    if (not defined($apriori)) { # we assume nothing
        return defined($bpriori) || ((rand > 0.5) ? 1 : -1);
    }
    elsif (not defined($bpriori)) {
        return -1;
    }
    int($apriori) <=> int($bpriori) || ((rand > 0.5) ? 1 : -1);
}

sub _triage {
    sort byPriority @_;
}

sub services {
    my $self = shift;
    my $xrds = $self->{xrds};
    return @{$self->{services}} if(defined($self->{services}));
    my @svc_nodes = sort byPriority
            $xrds->findnodes("/xrds:XRDS/xrd:XRD[last()]/xrd:Service");
    my @services;
    for(@svc_nodes) {
        push @services, Net::Yadis::Service->new($xrds, $_);
    }
    $self->{services} = \@services;
    return @services;
}

sub services_of_type {
    my $self = shift;
    my $typere = shift;
    
    my @allservices = $self->services;
    
    my @typeservices;
    for (@allservices) {
        push @typeservices, $_ if $_->is_type($typere);
    }
    return @typeservices;
}


# Hey, a perl generator! sequential calls will return the services one 
# at a time, in ascending priority order with ties randomly decided.
# make sure that the type argument is identical for each call, or the list
# will start again from the top.
sub service_of_type {
    my $self = shift;
    my $typere = shift;

    # remaining services of type
    my $rsot = $self->{rsot};
    my @remaining_services;
    if (defined($rsot->{$typere})) {
        @remaining_services = @{$rsot->{$typere}};
    }
    else {
        @remaining_services = $self->services_of_type($typere);
    }
    my $service = shift @remaining_services;
    $rsot->{$typere} = \@remaining_services;
    $self->{rsot}=$rsot;
    return $service;
}

1;

package Net::Yadis::Service;

#typere: regexp or string
sub is_type {
    my $self = shift;
    my $typere = shift;
     
    my $xrds = $self->{xrds};
    my $typenodes = $xrds->findnodes("./xrd:Type", $self->{node});
    my $is_type = 0;
    while($typenodes->size) {
        # string_value contains the first node's value <shrug>
        if ($typenodes->string_value =~ qr{$typere}) {
            $is_type = 1;
            last;
        }
        $typenodes->shift;
    }
    return $is_type;
}

sub types {
    my $self = shift;
    
    my $xrds = $self->{xrds};
    my @typenodes = $xrds->findnodes("./xrd:Type", $self->{node});
    my @types;
    for my $tn (@typenodes) {
        push @types, $xrds->getNodeText($tn);
    }
    return @types;
}

sub uris {
    my $self = shift;
    
    my $xrds = $self->{xrds};
    my @urinodes = Net::Yadis::_triage $xrds->findnodes("./xrd:URI", $self->{node});
    my @uris;
    for my $un (@urinodes) {
        push @uris, $xrds->getNodeText($un);
    }
    return @uris;
}

# another perl 'generator'. sequential calls will return the uris one 
# at a time, in ascending priority order with ties randomly decided
sub uri {
    my $self = shift;
    my @untried_uris;
    if (defined($self->{untried_uris})) {
        @untried_uris = @{$self->{untried_uris}};
    } else {
        @untried_uris = $self->uris;
    }
    my $uri = shift (@untried_uris);
    $self->{untried_uris} = \@untried_uris;
    return $uri;
}

sub getAttribute {
    my $self = shift;
    my $key = shift;
    my $node = $self->{node};
    $node->getAttribute($key);
}

sub findTag {
    my $self = shift;
    my $tagname = shift;
    my $namespace = shift;

    my $xrds = $self->{xrds};
    my $svcnode = $self->{node};
    
    my $value;
    if($namespace) {
        $xrds->set_namespace("asdf", $namespace);
        $value = $xrds->findvalue("./asdf:$tagname", $svcnode);
    }
    else {
        $value = $xrds->findvalue("./$tagname", $svcnode);
    }
    
    return $value;
}
    
sub new {
    my $caller = shift;
    my ($xrds, $node) = @_;

    my $class = ref($caller) || $caller;

    my $self = {
        xrds => $xrds,
        node => $node,
    };

    bless($self, $class);
}

1;
