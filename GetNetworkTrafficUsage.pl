# Sintax perl networktraffic.pl -i eth0

BEGIN {
	eval { require Time::HiRes; };
	if ($@) {
		warn "You don't have Time::HiRes installed. Fallback to perl's built-in time functions";
	} else {
		import Time::HiRes qw(time);
	}
};

use strict;
use POSIX qw(strftime);
use Getopt::Std;

my $PROC_NET_DEV = '/proc/net/dev';	# proc device to get the network statistics
my $SLEEP_INTERVAL = 1;

my $def_show_fields = ('bytes/k,packets,errs/M,out.colls');
my $guess_field_length = 8;
my %field_length_taken = 
	( 'k' => 3, 'K' => 3,
		'm' => 6, 'M' => 6,
		'u' => 2,
		1 => 0
	);
my %field_data_taken = 
	( 'k' => 1000, 'K' => 1024,
		'm' => 1000000, 'M' => 1048576,
		'u' => 512,
		1 => 1
	);


my %dev_ignore_show =
	(
	'list' => 'lo',
	'type' => 0,	# 0 - ignore, 1 - show
	);

my $proc_net_dev_title_line;
my %in_fields;
my %out_fields;
my $dev_show;

my $start_time;
my $end_time;
my @total;

my @show_fields = ();
my @show_fields_unit = ();
my @show_fields_length = ();

my $max_run = 0;
my $inffinity_run = 1;

sub
init()
{
	if (open (DEV, "<", $PROC_NET_DEV)) {
		$proc_net_dev_title_line = 0;
		
		my $part1type = 'in';
		my $part2type = 'out';
		while (<DEV>) {
			last if (/^\s*[\w\d]+:/);
			++$proc_net_dev_title_line;
			
			chomp;
			my ($devname, $part1, $part2) = split(/\s*\|\s*/);

			my @types1 = split(/\s+/, $part1);
			my @types2 = split(/\s+/, $part2);

			if (scalar(@types1) > 1) {
				if ($part1type eq 'in') {
					for (my $i = 0; $i < scalar(@types1); ++$i) {
						$in_fields{$types1[$i]} = $i;
					}
				} elsif ($part1type eq 'out') {
					for (my $i = 0; $i < scalar(@types1); ++$i) {
						$out_fields{$types1[$i]} = $i;
					}
				} else {
					die "unknown type $part1type";
				}
				
				if ($part2type eq 'in') {
					for (my $i = 0; $i < scalar(@types2); ++$i) {
						$in_fields{$types2[$i]} = $i + scalar(@types1);
					}
				} elsif ($part2type eq 'out') {
					for (my $i = 0; $i < scalar(@types2); ++$i) {
						$out_fields{$types2[$i]} = $i + scalar(@types1);
					}
				} else {
					die "unknown type $part2type";
				}
				
			} else {
				if ($types1[0] =~ /^(receive|recv|in)$/i) {
					$part1type = 'in'; $part2type = 'out';
				} else {
					$part1type = 'out'; $part2type = 'in';
				}
			}
		}

		close (DEV);
	} # endif (open (DEV, "<", "/proc/net/dev"))
	else
	{
		die "Unsupported /proc implementation. We can show you nothing.";
	}
}

sub
ntParseFields($)
{
	my $fieldDesc = shift;
	my @in_f;
	my @out_f;

	foreach (split(/\s*,\s*/, $fieldDesc)) {
		if (lc(substr($_, 0, 3)) eq 'in.') {
			push @in_f, $_;
		} elsif (lc(substr($_, 0, 4)) eq 'out.') {
			push @out_f, $_;
		} else {
			push @in_f, 'in.' . $_;
			push @out_f, 'out.' . $_;
		}
	}

	@show_fields = (@in_f, @out_f);
	foreach (@show_fields) {
		if (/\/(\w)$/) {
			if (lc($1) ne 'k' && lc($1) ne 'm' && lc($1) ne 'u') {
				die "unknown unit \"$1\"";
			}
			push @show_fields_unit, $1;
			s/\/\w$//;
		} else {
			push @show_fields_unit, 1;
		}
	}
}

sub
valueInArray($\@;$)
{
	my $value = shift;
	my $tmp = shift;
	my @array = @{$tmp};
	my $ignore_cases = shift;

	if ($ignore_cases) {
		$value = lc($value);
		@array = map { lc } @array;
	}
	
	foreach (@array) {
		return 1 if ($value eq $_);
	}

	return 0;
}

sub
readProcDevNet()
{
	my %result = ();
	
	open (DEV, "<", $PROC_NET_DEV);
	for (my $i = 0; $i < $proc_net_dev_title_line; ++$i) {
		<DEV>;
	}

	while (<DEV>) {
		my ($devname, $data) = split(/:/);

		$devname =~ s/^\s*//;
		$devname =~ s/\s*$//;

		my @devs = split(/\s*,\s*/, $dev_ignore_show{'list'});
		if ( $dev_ignore_show{'type'} ) {
			# show this devices only
			next unless (valueInArray($devname, @devs, 1));
		} else {
			# ignore this device
			next if (valueInArray($devname, @devs, 1));
		}

		chomp $data;
		$data =~ s/^\s*//;
		$data =~ s/\s*$//;
		my @datas = split(/\s+/, $data);

		my @tmp = ();
		
		foreach (@show_fields) {
			my ($type, $name) = split(/\./);
			if ($type eq 'in') {
				if (exists $in_fields{$name}) {
					push @tmp, int($datas[$in_fields{$name}]);
				} else {
					warn "wrong field name in.$name";
					push @tmp, 0;
				}
			} elsif ($type eq 'out') {
				if (exists $out_fields{$name}) {
					push @tmp, int($datas[$out_fields{$name}]);
				} else {
					warn "wrong field name out.$name";
					push @tmp, 0;
				}
			} else {
				warn "wrong type $type.$name";
				push @tmp, 0;
			}
		}

		$result{$devname} = \@tmp;
	}
	close (DEV);

	return \%result;
}

sub
max($$)
{
	return $_[0] > $_[1] ? $_[0] : $_[1];
}

sub
ntSub(\@\@;$)
{
	my $array1 = shift;
	my $array2 = shift;
	my $maxuint = shift || 4294967295;

	my @result = ();
	
	my $maxi = max(scalar(@$array1), scalar(@$array2));
	for (my $i = 0; $i < $maxi; ++$i) {
		my $num1 = $array1->[$i] || 0;
		my $num2 = $array2->[$i] || 0;

		$num1 -= $num2;
		$num1 += $maxuint if ($num1 < 0);
		push @result, $num1;
	}

	return \@result;
}

sub
ntCalcRate($$\%\%)
{
	my $time1 = shift;
	my $time2 = shift;
	my $data1 = shift;
	my $data2 = shift;

	my $timeEpo = $time2 - $time1;
	my $subResult;
	my @result = ();
	foreach my $dev (keys %$data1) {
		$subResult = ntSub(@{$data2->{$dev}}, @{$data1->{$dev}});
		for (my $i = 0 ; $i < scalar(@$subResult); ++$i) {
			$result[$i] += $subResult->[$i];
		}
	}

	$end_time = $time2;
	for (my $i = 0; $i < scalar(@result); ++$i) {
		$total[$i] += $result[$i];
		$result[$i] /= $field_data_taken{$show_fields_unit[$i]} * $timeEpo;
	}
	wantarray() ? @result : \@result;
}

my $title;
sub
ntTitle()
{
	if (defined $title) {
		print $title;
		return;
	}
	
	my @format1;
	my @name1;
	my @format2;
	my @name2;
	my $nflag;
	my $last_2nd;
	my $dev = '(' . $dev_show . ')';
	
	push @format1, '@' . '|' x max(length($dev) - 1, 7);	# time
	push @name1, $dev;
	push @format2, '@' . '>' x (length($format1[0]) - 1);
	push @name2, 'time';
	$last_2nd = 1;
	
	for (my $i = 0; $i < scalar(@show_fields); ++$i) {
		my ($type, $name) = split(/\./, $show_fields[$i]);
		$name = $show_fields_unit[$i] . $name if ($show_fields_unit[$i] != 1);
		push @name2, $name;
		$show_fields_length[$i] = max($guess_field_length - $field_length_taken{$show_fields_unit[$i]}, length($name) + 1);
		push @format2, '@' . '>' x ($show_fields_length[$i] - 1);

		if (!defined $nflag) {
			if (lc($type) eq 'in') {
				$nflag = 1;
			} elsif (lc($type) eq 'out') {
				$nflag = 2;
			} else {
				die "...";
			}
		} elsif ($nflag == 1) {
			if (lc($type) eq 'in') {
			} elsif (lc($type) eq 'out') {
				$nflag = 2;
				push @name1, 'input';
				push @format1, '@' . '|' x (length( join(' ', @format2[$last_2nd .. $#format2-1]) ) - 1);
				$last_2nd = $#format2;
			} else {
				die '...';
			}
		} elsif ($nflag == 2) {
			if (lc($type) eq 'in') {
				$nflag = 1;
				push @name1, 'output';
				push @format1, '@' . '|' x (length( join(' ', @format2[$last_2nd .. $#format2-1]) ) - 1);
				$last_2nd = $#format2;
			} elsif (lc($type) eq 'out') {
			} else {
				die '...';
			}
		} else {
			die "...?";
		}
	}
	
	if ($nflag == 1) {
		push @name1, 'input';
		push @format1, '@' . '|' x (length( join(' ', @format2[$last_2nd .. $#format2]) ) - 1);
	} elsif ($nflag == 2) {
		push @name1, 'output';
		push @format1, '@' . '|' x (length( join(' ', @format2[$last_2nd .. $#format2]) ) - 1);
	} else {
		die "...";
	}

	formline join('*', @format1) . "\n", @name1;
	formline join(' ', @format2) . "\n", @name2;
	$title = $^A;
	$^A = '';
	
	print $title;
	return;
}

my $lineformat;
sub
ntLine($@)
{
	my $the_time = strftime("%H:%M:%S", localtime(shift));
	if (!defined $lineformat) {
		
		my @format = ();
		my $dev = '(' . $dev_show . ')';
	
		push @format, '@' . '>' x max(length($dev) - 1, 7);
		for (my $i = 0; $i < scalar(@show_fields_length); ++$i) {
			push @format, '@' . '#' x ($show_fields_length[$i] - 1);
		}

		$lineformat = join(' ', @format);
	}
	
	formline $lineformat, $the_time, @_;
	print $^A, "\n";
	$^A = '';
}

sub
ntStatics()
{
	my $timeEpo = $end_time - $start_time;
	
	printf("\n\nStatics: begin at %s\tend at %s\n",
		strftime("%H:%M:%S", localtime($start_time)),
		strftime("%H:%M:%S", localtime($end_time)) );
	ntTitle();
	
	for (my $i = 0; $i < scalar(@total); ++$i) {
		$total[$i] /= $timeEpo * $field_data_taken{$show_fields_unit[$i]};
	}
	ntLine($end_time, @total);
	exit(0);
}

sub
ntParseArgument(\%)
{
	my $arg = shift;

	foreach my $keyname (keys %{$arg}) {
		if ($keyname eq 'i') {
			# interface to show
			$dev_ignore_show{'list'} = $arg->{'i'};
			$dev_ignore_show{'type'} = 1;
		} elsif ($keyname eq 'I') {
			# interface to ignore
			$dev_ignore_show{'list'} = $arg->{'I'};
			$dev_ignore_show{'type'} = 0;
		} elsif ($keyname eq 'c') {
            $max_run = $arg->{'c'};
            $inffinity_run = 0;
        }
	}

	return;
}

sub
ntShowHelp($)
{
	print <<"EOF";
    nettraf - Show the network traffic in a linux box.
        nettraf will get the statistics from the proc file system ( NORMALLY, /proc/net/dev)

        i			Interface list to show.
        I			Ignore interface list.
        c           Max show lines.
EOF
	exit($_[0]);
}

###########################
# main
###########################
{
	my %arguments;
	unless (getopts('i:I:c:', \%arguments)) {
		ntShowHelp(-1);
	}

	ntParseArgument(%arguments);
	init();
	$SIG{INT} = \&ntStatics;
	ntParseFields($def_show_fields);
	my $this_time = time;
	my $this_data = readProcDevNet();
	$start_time = $this_time;

	my $line_show_count = 0;	
	$dev_show = join('+', keys %$this_data);
	while ($inffinity_run || $line_show_count < $max_run) {
		ntTitle() if (($line_show_count++ % 25) == 0);

		sleep($SLEEP_INTERVAL);
		my $last_data = $this_data;
		my $last_time = $this_time;
		$this_time = time;
		$this_data = readProcDevNet();

		my $calcResult = ntCalcRate($last_time, $this_time, %$last_data, %$this_data);
		ntLine($this_time, @$calcResult);
	}
    ntStatics();
}
