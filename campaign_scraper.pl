###!/usr/bin/perl

use Data::Dumper;
use REST::Client;
use JSON;
use URI::Encode qw(uri_encode uri_decode);
use GD::Graph::pie;
use XML::Simple;

my $apikey = '<API KEY>';
my $baseurl = 'http://transparencydata.org/api/1.0/';

my $senator_list = '<SENATOR LIST>';

my $outdir = '/tmp/senators';

my $rest_obj = REST::Client->new();
$rest_obj->setFollow(1);
my $json = JSON->new->allow_nonref;

my $senator_ref = XMLin($senator_list);
my @members = @{$senator_ref->{member}};

open(INDEX, ">$outdir/index.html");
binmode INDEX;

print INDEX "<html>\n<head>\n<title>Senator Campaign Contributions</title>\n</head>\n<body>\n";

foreach $member ( @members ) {
	my $name = $member->{first_name} . " " . $member->{last_name};

	my $entity = fetch_entity($name, 'politician');

	my $entity_hash = shift (@$entity);

	my $id = $entity_hash->{id};

	my $cycle = 2014;

	do {
		print INDEX "<a href=\"$id-$cycle.html\">$name ([$cycle] $entity_hash->{party}, $entity_hash->{state})</a>\n<br />\n";

		open(OUTFILE, ">$outdir/$id-$cycle.html");

		print OUTFILE "<html>\n<head>\n<title>$name - $cycle</title>\n</head>\n<body>\n";
		print OUTFILE "<h1>$name</h1>\n<br />\n<h2>$entity_hash->{state}</h2>\n<br />\n";

		if( $entity_hash->{party} eq "D" ) {
			print OUTFILE "<h3>Democrat</h3>\n";
		} else {	
			print OUTFILE "<h3>Republican</h3>\n";
		}

		print OUTFILE "<br />\n<b>$cycle</b>\n<br />\n";

		my @contribs = fetch_contributions($name, $cycle);

		process_contribs($name, $id, $cycle, @contribs);	

		print OUTFILE "</body>\n</html>\n";

		close(OUTFILE);

		$cycle -= 2;

	} while ( $cycle > 2010 );		

	print INDEX "</body>\n</html>\n";
	close(INDEX);

}
exit;

sub new_gd_pie {
	my $graph = GD::Graph::pie->new();
	$graph->set(suppress_angle => 10);

	return $graph;
}

sub fetch_entity {
	my ($entity_name, $entity_type) = @_;

	my $entity_url = $baseurl . "entities.json?apikey=$apikey&search=$entity_name&type=$entity_type";

	my $encoded_url = uri_encode($entity_url);
	
	$rest_obj->GET($encoded_url);

	my $entity_raw = $rest_obj->responseContent();

	my $entity = $json->decode($entity_raw);

	return $entity;
}
	
sub fetch_contributions {
	my ($entity_name, $cycle) = @_;

	my $page = 1;	

	my $result;
	my @contributions;

	my $entity_url = $baseurl . "contributions.json?apikey=$apikey&recipient_ft=$entity_name&per_page=10000&cycle=$cycle&";

	my $encoded_url = uri_encode($entity_url);
	
	do {
		$rest_obj->GET($encoded_url . "page=$page");
		$result = $json->decode($rest_obj->responseContent());

		push(@contributions, @$result);

		++$page;
	}while ( @$result > 0 );

	return @contributions;
}

sub process_contribs {
	my ($entity, $id, $cycle, @contributions) = @_;
	my @corp;
	my @corp_values;
	my @corp_percents;
	my %corp_amount_summary;
	my @indiv;
	my @indiv_values;
	my @indiv_percents;
	my %indiv_occupations;
	my %indiv_amount_summary;
	my %contrib_cities;

	my $corp_total = 0;
	my $indiv_total = 0;
	my $total = 0;

	print OUTFILE "<h4>Contributions</h4>\n<br />\n";

	foreach (@contributions) {
		# print Dumper($_);
		if( $_->{amount} > 0 ) {
			if( $_->{contributor_type} eq "C" ) {
				my $entity_name = $_->{organization_name};
			}elsif ( $_->{contributor_type} eq "I" ) {
				my $entity_name = $_->{contributor_name};
			}else {
				my $entity_name = $_->{organization_name} eq '   ' ? $_->{organization_name} : $_->{contributor_name};
			}

			if( $_->{contributor_type} eq "I" ) {
				push (@indiv, $_->{contributor_name});
				push (@indiv_values, $_->{amount});

				$indiv_total += $_->{amount};

				if( exists $indiv_occupations{$_->{contributor_occupation}} ) {
					$indiv_occupations{$_->{contributor_occupation}} += 1.0;
				} else {
					$indiv_occupations{$_->{contributor_occupation}} = 1.0;
				}

				if( exists $indiv_amount_summary{$_->{amount}} ) {
					$indiv_amount_summary{$_->{amount}} += 1.0;
				} else {
					$indiv_amount_summary{$_->{amount}} = 1.0;
				}

			}else {
				push (@corp, $_->{organization_name});
				push (@corp_values, $_->{amount});

				$corp_total += $_->{amount};

				if( exists $corp_amount_summary{$_->{amount}} ) {
					$corp_amount_summary{$_->{amount}} += 1.0;
				} else {
					$corp_amount_summary{$_->{amount}} = 1.0;
				}
			}

			if( exists $contrib_cities{$_->{contributor_city}} ) {
				$contrib_cities{$_->{contributor_city}} += 1.0;
			} else {
				$contrib_cities{$_->{contributor_city}} = 1.0;
			}
		}
	};

	$total = $corp_total + $indiv_total;

	# Prevent division by 0 if we end up with a zero total
	if ( $total == 0 ) {
		return;
	}

	print OUTFILE "<b>Total Contributions: </b>(\$$total)<br />\n";
	print OUTFILE @indiv . " <b>Individuals</b> \$$indiv_total\t" . @corp . " <b>Corporations</b> \$$corp_total<br />\n";
	print OUTFILE "<b>Individuals:</b> " . ($indiv_total / $total) * 100 . 
			"&#37; <b>Corporations:</b> " . ($corp_total / $total) * 100 . "&#37;<br />\n";
	
	print OUTFILE "<table cols=2>\n<tr><td colspan=2>Individual Occupations</td></tr>\n<tr>";
	print OUTFILE "<td><b>Occupation</b></td><td><b>Count</b></td></tr>\n";

	foreach (keys %indiv_occupations) {
		print OUTFILE "<tr><td>$_</td><td>$indiv_occupations{$_}</td></tr>\n";
	}

	print OUTFILE "</table>\n<br />\n";

	print OUTFILE "<table cols=2>\n<tr><td colspan=2>Individual Contributions</td></tr>\n<tr>";
	print OUTFILE "<td><b>Contribution Amount</b></td><td><b>Count</b></td></tr>\n";

	foreach ( keys %indiv_amount_summary ) {
		print OUTFILE "<tr><td>\$$_</td><td>$indiv_amount_summary{$_}</td></tr>\n";
	}

	print OUTFILE "</table>\n<br />\n";

	print OUTFILE "<table cols=2>\n<tr><td colspan=2>Corporate Contributions</td></tr>\n<tr>";
	print OUTFILE "<td><b>Contribution Amount</b></td><td><b>Count</b></td></tr>\n";

	foreach ( keys %corp_amount_summary ) {
		print OUTFILE "<tr><td>\$$_</td><td>$corp_amount_summary{$_}</td></tr>\n";
	}

	print OUTFILE "</table>\n<br />\n";

	print OUTFILE "<table cols=2>\n<tr><td colspan=2>Contributor Cities</td></tr>\n<tr>";
	print OUTFILE "<td><b>City</b></td><td><b>Count</b></td></tr>\n";

	foreach ( keys %contrib_cities ) {
		print OUTFILE "<tr><td>$_</td><td>$contrib_cities{$_}</td></tr>\n";
	}

	print OUTFILE "</table>\n<br />\n";

# This Crashes GD
if (0) {
	foreach (@indiv_values) {
		my $percent = ($_ / $total) * 100;

		push (@indiv_percents, $percent);
	}

	foreach (@corp_values) {
		my $percent = ($_ / $total) * 100;

		push (@corp_percents, $percent);
	}

	print "Graphing (" . @indiv . " Individuals ) (" . @indiv_percents . " percents )\n";

	my @gdata = ( [@indiv], [@indiv_percents]);
	print Dumper(@gdata);
	my $gd = $graph->plot(\@gdata);

	open(IMG, ">/tmp/$entity_name-indiv.png");
	binmode IMG;
	print IMG $gd->png;
} # if 0

	# Graph Individuals vs. Corporations
	my @gdata = ( ["Individuals", "Corporations"], [$indiv_total, $corp_total] );
	my $graph = new_gd_pie();
	my $gd = $graph->plot(\@gdata);

	if( $graph->error ) {
		return;
	}

	open(IMG, ">$outdir/img/$id-$cycle-summary.png");
	binmode IMG;
	print IMG $gd->png;
	close(IMG);

	print OUTFILE "<img src=\"img/$id-$cycle-summary.png\" title=\"Individuals vs. Corporations\" />\n<br />\n";

	# Graph Occupations vs. Count
	my @occupations;
	my @occ_count;

	# Simplify for GD
	if( ! exists $indiv_occupations{OTHER} ) {
		$indiv_occupations{OTHER} = 0.0;
	}

	foreach ( keys %indiv_occupations ) {
		if( $indiv_occupations{$_} < 5 ) {
			$indiv_occupations{OTHER} += $_indiv_occupations{$_};
			
			delete $indiv_occupations{$_};
		}
	}
		
	foreach ( keys %indiv_occupations ) {
		push (@occupations, $_);
		push (@occ_count, $indiv_occupations{$_});
	}

	my @occ_data = ( \@occupations, \@occ_count );
	$graph = new_gd_pie();
	my $gd_occ = $graph->plot(\@occ_data);
	
	if( $graph->error ) {
		return;
	}

	open(IMG, ">$outdir/img/$id-$cycle-occupations.png");
	binmode IMG;
	print IMG $gd_occ->png;
	close(IMG);
	
	print OUTFILE "<img src=\"img/$id-$cycle-occupations.png\" title=\"Individuals Contributor Occupations\" />\n<br />\n";

	# Graph Individual Contribution Amounts vs. count
	my @iamounts;
	my @icounts;

	# Simplify because GD is stupid!
	if( ! exists $indiv_amount_summary{OTHER} ) {
		$indiv_amount_summary{OTHER} = 0.00;
	}	

	foreach ( keys %indiv_amount_summary) {
		if( $indiv_amount_summary{$_} < 5 && $_ < 10000  ) {
			$indiv_amount_summary{OTHER} += $indiv_amount_summary{$_};
			
			delete $indiv_amount_summary{$_};
		}
	}

	foreach ( keys %indiv_amount_summary) {
		push (@iamounts, $_);
		push (@icounts, $indiv_amount_summary{$_});
	}

	my @i_data = ( \@iamounts, \@icounts);
	$graph = new_gd_pie();
	my $gd_iamt = $graph->plot(\@i_data);
	
	if( $graph->error ) {
		return;
	}

	open(IMG, ">$outdir/img/$id-$cycle-individual_amounts.png");
	binmode IMG;
	print IMG $gd_iamt->png;
	close(IMG);
	
	print OUTFILE "<img src=\"img/$id-$cycle-individual_amounts.png\" title=\"Individuals Contribution Amounts\" />\n<br />\n";

	# Graph Corporate Contribution Amounts vs. count
	my @camounts;
	my @ccounts;

	# Simplify for GD being retarded
	if( ! exists $corp_amount_summary{OTHER} ) {
		$corp_amount_summary{OTHER} = 0.0;
	}

	foreach ( keys %corp_amount_summary) {
		if( $corp_amount_summary{$_} < 5 && $_ < 10000 ) {
			$corp_amount_summary{OTHER} += $corp_amount_summary{$_};

			delete $corp_amount_summary{$_};
		}
	}

	foreach ( keys %corp_amount_summary) {
		push (@camounts, $_);
		push (@ccounts, $corp_amount_summary{$_});
	}

	my @c_data = ( \@camounts, \@ccounts);
	$graph = new_gd_pie();
	my $gd_camt = $graph->plot(\@c_data);
	
	if( $graph->error ) {
		return;
	}

	open(IMG, ">$outdir/img/$id-$cycle-corporate_amounts.png");
	binmode IMG;
	print IMG $gd_camt->png;
	close(IMG);
	
	print OUTFILE "<img src=\"img/$id-$cycle-corporate_amounts.png\" title=\"Corporate Contribution Amounts\" />\n<br />\n";

	# Graph Cities vs. Count
	my @cities;
	my @citycounts;

	# Pre-process this, and consolidate "small" cities to make GD happier
	if( ! exists $contrib_cities{Other} ) {
		$contrib_cities{Other} = 1.0;
	}

	foreach ( keys %contrib_cities ) {
		if( $contrib_cities{$_} <= 10.0 || length $_ < 2 ) {
			$contrib_cities{Other} += $contrib_cities{$_};
		
			delete $contrib_cities{$_};
		}
	}

	foreach ( keys %contrib_cities ) {
		push (@cities, $_);
		push (@citycounts, $contrib_cities{$_});
	}


	my @city_data = ( \@cities, \@citycounts);
	$graph = new_gd_pie();
	my $gd_cities = $graph->plot(\@city_data);
	
	if( $graph->error ) {
		return;
	}

	open(IMG, ">$outdir/img/$id-$cycle-cities.png");
	binmode IMG;
	print IMG $gd_cities->png;
	close(IMG);
	
	print OUTFILE "<img src=\"img/$id-$cycle-cities.png\" title=\"Contribution Cities\" />\n<br />\n";
}
