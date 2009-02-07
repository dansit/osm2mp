#!/usr/bin/perl


##
##  Required packages: Template-toolkit, Getopt::Long
##  See http://cpan.org/ or use PPM (Perl package manager)
##


####    Settings

my $version = "0.65";

my $cfgpoi      = "poi.cfg";
my $cfgpoly     = "poly.cfg";
my $cfgheader   = "header.tpl";


my $codepage    = "1251";
my $mapid       = "88888888";
my $mapname     = "OSM routable";

my $defaultcountry = "Earth";
my $defaultregion  = "OSM";
my $defaultcity    = "Unknown";

my $mergeroads     = 1;
my $mergecos       = 0.2;

my $detectdupes    = 1;

my $splitroads     = 1;

my $fixclosenodes  = 1;
my $fixclosedist   = 5.5;

my $restrictions   = 1;

my $nocodepage;

my $nametaglist    = "name,ref,int_ref";
my $upcase         = 0;

my $bbox;
my $background     = 0;

my %yesno = (  "yes"            => 1,
               "true"           => 1,
               "1"              => 1,
               "permissive"     => 1,
               "no"             => 0,
               "false"          => 0,
               "0"              => 0,
               "private"        => 0);

use Getopt::Long;
$result = GetOptions (
                        "cfgpoi=s"              => \$cfgpoi,
                        "cfgpoly=s"             => \$cfgpoly,
                        "header=s"              => \$cfgheader,
                        "mapid=s"               => \$mapid,
                        "mapname=s"             => \$mapname,
                        "codepage=s"            => \$codepage,
                        "nocodepage"            => \$nocodepage,
                        "mergeroads!"           => \$mergeroads,
                        "mergecos=f"            => \$mergecos,
                        "detectdupes!"          => \$detectdupes,
                        "splitroads!"           => \$splitroads,
                        "fixclosenodes!"        => \$fixclosenodes,
                        "fixclosedist=f"        => \$fixclosedist,
                        "restrictions!"         => \$restrictions,
                        "defaultcountry=s"      => \$defaultcountry,
                        "defaultregion=s"       => \$defaultregion,
                        "defaultcity=s"         => \$defaultcity,
                        "nametaglist=s"         => \$nametaglist,
                        "upcase!"               => \$upcase,
                        "bbox=s"                => \$bbox,
                        "background!",          => \$background,
                      );

undef $codepage         if ($nocodepage);



####    Action

use strict;
use Template;

print STDERR "\n  ---|   OSM -> MP converter  $version   (c) 2008,2009  liosha, xliosha\@gmail.com\n\n";


if ($ARGV[0] eq "") {
    print "Usage:  osm2mp.pl [options] file.osm > file.mp

Possible options:

    --cfgpoi <file>           poi config
    --cfgpoly <file>          way config
    --header <file>           header template

    --bbox <bbox>             comma-separated minlon,minlat,maxlon,maxlat
    --background              create background object

    --mapid <id>              map id
    --mapname <name>          map name

    --codepage <num>          codepage number (e.g. 1252)
    --nocodepage              leave all labels in utf-8
    --upcase                  convert all labels to upper case

    --nametaglist <list>      comma-separated list of tags for Label

    --mergeroads              merge same ways
    --nomergeroads
    --mergecos <cosine>       maximum allowed angle between roads to merge

    --detectdupes             detect road duplicates
    --nodetectdupes

    --splitroads              split long and self-intersecting roads
    --nosplitroads            (cgpsmapper-specific)

    --fixclosenodes           enlarge distance between too close nodes
    --nofixclosenodes         (cgpsmapper-specific)
    --fixclosedist (dist)     minimum allowed distance (default 5.5 metres)

    --restrictions            process turn restrictions
    --norestrictions

    --defaultcountry <name>   default data for street indexing
    --defaultregion <name>
    --defaultcity <name>
\n";
    exit;
}


####    Reading configs

my ($minlon, $minlat, $maxlon, $maxlat) = split /,/, $bbox;

my %poitype;

open CFG, $cfgpoi;
while (<CFG>) {
   if ( (!$_) || /^\s*[\#\;]/ ) { next; }
   chomp;
   my ($k, $v, $type, $llev, $hlev, $city) = split /\s+/;
   if ($type) {
     $llev = 0          if ($llev eq "");
     $hlev = 1          if ($hlev eq "");
     $city = (($city ne "") ? 1 : 0);
     $poitype{"$k=$v"} = [ $type, $llev, $hlev, $city ];
   }
}
close CFG;


my %polytype;

open CFG, $cfgpoly;
while (<CFG>) {
   if ( (!$_) || /^\s*[\#\;]/ ) { next; }
   chomp;

   my $prio = 0;
   my ($k, $v, $mode, $type, $llev, $hlev, $rp, @p) = split /\s+/;

   if ($type) {
     if ($type =~ /(.+),(\d)/) {     $type = $1;    $prio = $2;    }
     $llev = 0          if ($llev eq "");
     $hlev = 1          if ($hlev eq "");

     $polytype{"$k=$v"} = [ $mode, $type, $prio, $llev, $hlev, $rp ];
   }
}
close CFG;


my @nametagarray = split (/,/, $nametaglist);



####    Header

my $tmp = Template->new({ABSOLUTE => 1});
$tmp->process ($cfgheader, {
        mapid           => $mapid,
        mapname         => $mapname,
        codepage        => $codepage,
        defaultcountry  => $defaultcountry,
        defaultregion   => $defaultregion,
      }) || die $tmp->error();


####    Info


use POSIX qw(strftime);
print "\n; Converted from OpenStreetMap data with  osm2mp $version  (" . strftime ("%Y-%m-%d %H:%M:%S", localtime) . ")\n\n";


open IN, $ARGV[0];
print STDERR "Processing file $ARGV[0]\n\n";



####    Background object (?)


if ($bbox && $background) {

    print "\n\n\n; ### Background\n\n";
    print  "[POLYGON]\n";
    print  "Type=0x4b\n";
    print  "EndLevel=9\n";
    print  "Data0=($minlat,$minlon), ($minlat,$maxlon), ($maxlat,$maxlon), ($maxlat,$minlon) \n";
    print  "[END]\n\n\n";

}




####    Loading nodes and writing POIs

my %nodes;

print STDERR "Loading nodes...          ";
print "\n\n\n; ### Points\n\n";

my $countpoi = 0;

my $id;
my $latlon;
my ($poi, $poiname);
my ($poihouse, $poistreet, $poicity, $poiregion, $poicountry, $poizip, $poiphone);
my $nameprio = 99;

while (<IN>) {
   last if /\<way/;

   if ( /\<node/ ) {
      /^.* id=["'](\-?\d+)["'].*lat=["'](\-?\d+\.?\d*)["'].*lon=["'](\-?\d+\.?\d*)["'].*$/;
      $id = $1;
      $latlon = "$2,$3";
      $nodes{$1} = $latlon;

      $poi = "";
      $poiname = "";
      $nameprio = 99;
      ($poihouse, $poistreet, $poicity, $poiregion, $poicountry, $poizip, $poiphone) = ("", "", "", "", "", "", "");
      next;
   }

   if ( /\<tag/ ) {
      /^.*k=["'](.*)["'].*v=["'](.*)["'].*$/;
      $poi = "$1=$2"                            if ($poitype{"$1=$2"});
      my $tagprio = indexof(\@nametagarray, $1);
      if ($tagprio>=0 && $tagprio<$nameprio) {
          $poiname = convert_string ($2);
          $nameprio = $tagprio;
      }

      $poistreet    = convert_string($2)        if ($1 eq "addr:street" );
      $poizip       = convert_string($2)        if ($1 eq "addr:postcode" );
      $poicity      = convert_string($2)        if ($1 eq "addr:city" );      
      $poiregion    = convert_string($2)        if ($1 eq "is_in:county");
      $poicountry   = convert_string($2)        if ($1 eq "is_in:country");

      # Navitel only (?)
      $poihouse     = convert_string($2)        if ($1 eq "addr:housenumber" );        
      $poiphone     = convert_string($2)        if ($1 eq "phone" );

      if ($1 eq "is_in") {
          ($poicity, my $region, my $country) = split (/,/, convert_string($2));
          $poiregion  = $region         if ($region);
          $poicountry = $country        if ($country);
      }
      
      next;
   }

   if ( /\<\/node/ && $poi && (!$bbox || insidebbox($latlon)) ) {

       $countpoi ++;
       my @type = @{$poitype{$poi}};

       print  "; NodeID = $id\n";
       print  "; $poi\n";
       print  "[POI]\n";
       printf "Type=%s\n",            $type[0];
       printf "Data%d=($latlon)\n",   $type[1];
       printf "EndLevel=%d\n",        $type[2]          if ($type[2] > $type[1]);
       printf "City=Y\n",                               if ($type[3]);
       print  "Label=$poiname\n"                        if ($poiname);

       print  "StreetDesc=$poistreet\n"                 if ($poistreet);
       printf "CityName=%s\n", $poicity ? $poicity : $defaultcity;
       print  "RegionName=$poiregion\n"                 if ($poiregion);
       print  "CountryName=$poicountry\n"               if ($poicountry);
       print  "Zip=$poizip\n"                           if ($poizip);

       print  "HouseNumber=$poihouse\n"                 if ($poihouse);
       print  "Phone=$poiphone\n"                       if ($poiphone);

       print  "[END]\n\n";
   }
}

printf STDERR "%d loaded, %d POIs dumped\n", scalar keys %nodes, $countpoi;






####    Skipping ways

my $waypos  = tell IN;
my $waystr  = $_;

while (<IN>) {     last if /\<relation/;     }

my $relpos  = tell IN;
my $relstr  = $_;






####    Loading relations

my %mpoly;
my %mpholes;

my %trest;
#my %waytr;
my %nodetr;


print STDERR "Loading relations...      ";

my $id;
my $reltype;

my $mp_outer;
my @mp_inner;

my ($tr_from, $tr_via, $tr_to, $tr_type);

while ($_) {

    if ( /\<relation/ ) {
        /^.* id=["'](\-?\d+)["'].*$/;

        $id = $1;
        undef $reltype;
        undef $mp_outer;        undef @mp_inner;
        undef $tr_from;         undef $tr_via;          
        undef $tr_to;           undef $tr_type;
        next;
    }

    if ( /\<member/ ) {
        /type=["'](\w+)["'].*ref=["'](\-?\d+)["'].*role=["'](\w+)["']/;

        $mp_outer = $2                  if ($3 eq "outer" && $1 eq "way");
        push @mp_inner, $2              if ($3 eq "inner" && $1 eq "way");

        $tr_from = $2                   if ($3 eq "from"  && $1 eq "way");
        $tr_to = $2                     if ($3 eq "to"    && $1 eq "way");
        $tr_via = $2                    if ($3 eq "via"   && $1 eq "node");

        next;
    }

    if ( /\<tag/ ) {
        /k=["'](\w+)["'].*v=["'](\w+)["']/;
        $reltype = $2                           if ( $1 eq "type" );
        $tr_type = $2                           if ( $1 eq "restriction" );
        next;
    }

    if ( /\<\/relation/ ) {
        if ( $reltype eq "multipolygon" ) {
            $mpoly{$mp_outer} = [ @mp_inner ];
            @mpholes{@mp_inner} = @mp_inner;
        }
        if ( $restrictions && $reltype eq "restriction" ) {
            $tr_to = $tr_from                   if ($tr_type eq "no_u_turn" && !$tr_to);

            if ( $tr_from && $tr_via && $tr_to ) {
                $trest{$id} = { node => $tr_via, 
                                type => ($tr_type =~ /^only_/) ? "only" : "no",
                                fr_way => $tr_from,   fr_dir => 0,   fr_pos => -1, 
                                to_way => $tr_to,     to_dir => 0,   to_pos => -1 };
                push @{$nodetr{$tr_via}}, $id;
            } else {
                print ";ERROR: Wrong restriction RelID=$id\n";
            }
        }
        next;
    }

} continue { $_ = <IN>; }

printf STDERR "%d multipolygons, %d turn restrictions\n", scalar keys %mpoly, scalar keys %trest;






####    Loading multipolygon holes and checking node dupes

print STDERR "Loading holes...          ";

seek IN, $waypos, 0;
$_ = $waystr;

   my $id;
   my @chain;
   my $dupcount;

while ($_) {

   last if /\<relation/;

   if ( /\<way/ ) {
      /^.* id=["'](\-?\d+)["'].*$/;

      $id = $1;
      @chain = ();
      $dupcount = 0;
      next;
   }

   if ( /\<nd/ ) {
      /^.*ref=["'](.*)["'].*$/;
      if ($nodes{$1}  &&  $1 ne $chain[-1] ) {
          push @chain, $1;
      } elsif ($nodes{$1}) {
          print "; ERROR: WayID=$id has dupes at ($nodes{$1})\n";
          $dupcount ++;
      }
      next;
   }

   if ( /\<\/way/ ) {

       ##       this way is multipolygon inner
       if ( $mpholes{$id} ) {
           $mpholes{$id} = [ @chain ];
       }
   }

} continue { $_ = <IN>; }

printf STDERR "%d loaded\n", scalar keys %mpholes;






####    Loading roads and writing other ways

my %rchain;
my %rprops;
my %risin;

my %xnodes;

print STDERR "Processing ways...        ";
print "\n\n\n; ### Lines and polygons\n\n";

seek IN, $waypos, 0;
$_ = $waystr;

my $countlines = 0;
my $countpolygons = 0;

my $id;
my @chain;
my @chainlist;
my $inbbox;

my ($poly, $polyname);
my $nameprio = 99;
my $isin;

my $speed;
my $polydir;
my ($polytoll, $polynoauto, $polynobus, $polynoped, $polynobic, $polynohgv);

while ($_) {

   last if /\<relation/;

   if ( /\<way/ ) {
      /^.* id=["'](\-?\d+)["'].*$/;

      $id = $1;

      @chain = ();
      @chainlist = ();
      $inbbox = 0;

      undef ($poly);
      undef ($polyname);
      $nameprio = 99;
      
      undef ($polydir);
      undef ($polytoll);
      undef ($polynoauto);
      undef ($polynobus);
      undef ($polynoped);
      undef ($polynobic);
      undef ($polynohgv);

      undef ($speed);

      undef ($isin);

      next;
   }

   if ( /\<nd/ ) {
      /^.*ref=["'](.*)["'].*$/;
      if ($nodes{$1}  &&  $1 ne $chain[-1] ) {
          push @chain, $1;
          if ($bbox) {
              if ( !$inbbox &&  insidebbox($nodes{$1}) )        { push @chainlist, ($#chain ? $#chain-1 : 0); }
              if (  $inbbox && !insidebbox($nodes{$1}) )        { push @chainlist, $#chain; }
              $inbbox = insidebbox($nodes{$1});
          }
      }
      next;
   }

   if ( /\<tag/ ) {
       /^.*k=["'](.*)["'].*v=["'](.*)["'].*$/;
       $poly       = "$1=$2"                    if ($polytype{"$1=$2"} && ($polytype{"$1=$2"}->[2] >= $polytype{$poly}->[2]));
       
       my $tagprio = indexof(\@nametagarray, $1);
       if ($tagprio>=0 && $tagprio<$nameprio) {
           $polyname = convert_string ($2);
           $nameprio = $tagprio;
       }
       
       $isin       = convert_string ($2)        if ($1 eq "is_in");

       $speed      = $2                         if ($1 eq "maxspeed" && $2>0);

       $polydir    = $yesno{$2}                 if ($1 eq "oneway");
       $polytoll   = $yesno{$2}                 if ($1 eq "toll");
       $polynoauto = 1 - $yesno{$2}             if ($1 eq "motorcar");
       $polynobus  = 1 - $yesno{$2}             if ($1 eq "psv");
       $polynoped  = 1 - $yesno{$2}             if ($1 eq "foot");
       $polynobic  = 1 - $yesno{$2}             if ($1 eq "bicycle");
       $polynohgv  = 1 - $yesno{$2}             if ($1 eq "hgv");
       $polynoauto = $polynobus = $polynoped = $polynobic = $polynohgv = 1 - $yesno{$2}
                                                if ($1 eq "access");
       $polynobic  = $polynoped = $yesno{$2}    if ($1 eq "motorroad");

       next;
   }

   if ( /\<\/way/ ) {

       if ( !$bbox )                    {   @chainlist = (0);   }
       if ( !($#chainlist % 2) )        {   push @chainlist, $#chain;   }

       ##       this way is road
 
       if ( $polytype{$poly}->[0] eq "r"  &&  scalar @chain <= 1 ) {
           print "; ERROR: Road WayID=$id has too few nodes at ($nodes{$chain[0]})\n";
       }
       if ( $polytype{$poly}->[0] eq "r"  &&  scalar @chain > 1 ) {
           my @rp = split /,/, $polytype{$poly}->[5];
           
           if (defined $speed) {
               if ($speed =~ /mph$/i)   {  $speed *= 1.61;  }
               $rp[0]  = speedcode($speed);               
           }

           $rp[2]  = $polydir                           if defined $polydir;
           $rp[3]  = $polytoll                          if defined $polytoll;
           $rp[5]  = $rp[6] = $rp[8] = $polynoauto      if defined $polynoauto;
           $rp[7]  = $polynobus                         if defined $polynobus;
           $rp[9]  = $polynoped                         if defined $polynoped;
           $rp[10] = $polynobic                         if defined $polynobic;
           $rp[11] = $polynohgv                         if defined $polynohgv;

           for (my $i=0; $i<$#chainlist+1; $i+=2) {
               $rchain{"$id:$i"} = [ @chain[$chainlist[$i]..$chainlist[$i+1]] ];
               $rprops{"$id:$i"} = [ $poly, $polyname, join (",",@rp) ];
               $risin{"$id:$i"}  = $isin         if ($isin);

               if ($bbox) {
                   if ( !insidebbox($nodes{$chain[$chainlist[$i]]}) ) {
                       $xnodes{ $chain[$chainlist[$i]] }        = 1;
                       $xnodes{ $chain[$chainlist[$i]+1] }      = 1;
                   }
                   if ( !insidebbox($nodes{$chain[$chainlist[$i+1]]}) ) {
                       $xnodes{ $chain[$chainlist[$i+1]] }      = 1;
                       $xnodes{ $chain[$chainlist[$i+1]-1] }    = 1;
                   }
               }
           }

           # processing associated turn restrictions

           if ($restrictions) {
               if ( $chainlist[0] == 0 ) {
                   for my $relid (@{$nodetr{$chain[0]}}) {
                       if ( $trest{$relid}->{fr_way} eq $id ) {  
                           $trest{$relid}->{fr_way} = "$id:0";
                           $trest{$relid}->{fr_dir} = -1;
                           $trest{$relid}->{fr_pos} = 0;
                       }
                       if ( $trest{$relid}->{to_way} eq $id ) {  
                           $trest{$relid}->{to_way} = "$id:0";
                           $trest{$relid}->{to_dir} = 1;
                           $trest{$relid}->{to_pos} = 0;
                       }
                   }
               }
               if ( $chainlist[-1] == $#chain ) {
                   for my $relid (@{$nodetr{$chain[-1]}}) {
                       if ( $trest{$relid}->{fr_way} eq $id ) {  
                           $trest{$relid}->{fr_way} = "$id:" . (($#chainlist-1)>>1);
                           $trest{$relid}->{fr_dir} = 1;
                           $trest{$relid}->{fr_pos} = $chainlist[-1] - $chainlist[-2];
                       }
                       if ( $trest{$relid}->{to_way} eq $id ) {  
                           $trest{$relid}->{to_way} = "$id:" . (($#chainlist-1)>>1);
                           $trest{$relid}->{to_dir} = -1;
                           $trest{$relid}->{to_pos} = $chainlist[-1] - $chainlist[-2];
                       }
                   }
               }
           }
       }


       ##       this way is map line

       if ( $polytype{$poly}->[0] eq "l" ) {
           my $d = "";
           if ( scalar @chain < 2 ) {
               print "; ERROR: WayID=$id has too few nodes at ($nodes{$chain[0]})\n";
               $d = "; ";
           }

           my @type = @{$polytype{$poly}};

           for (my $i=0; $i<$#chainlist+1; $i+=2) {
               $countlines ++;

               print  "; WayID = $id\n";
               print  "; $poly\n";
               print  "${d}[POLYLINE]\n";
               printf "${d}Type=%s\n",        $type[1];
               printf "${d}EndLevel=%d\n",    $type[4]              if ($type[4] > $type[3]);
               print  "${d}Label=$polyname\n"                       if ($polyname);
               print  "${d}DirIndicator=$polydir\n"                 if defined $polydir;
               printf "${d}Data%d=(%s)\n",    $type[3], join ("), (", @nodes{@chain[$chainlist[$i]..$chainlist[$i+1]]});
               print  "${d}[END]\n\n\n";
           }
       }


       ##       this way is map polygon

       if ( $polytype{$poly}->[0] eq "p" ) {
           my $d = "";
           if ( scalar @chain < 4 ) {
               print "; ERROR: WayID=$id has too few nodes near ($nodes{$chain[0]})\n";
               $d = "; ";
           }
           if ( $chain[0] ne $chain[-1] ) {
               print "; ERROR: area WayID=$id is not closed at ($nodes{$chain[0]})\n";
           }

           my @type = @{$polytype{$poly}};

           if (!$bbox || scalar @chainlist) {
               $countpolygons ++;

               print  "; WayID = $id\n";
               print  "; $poly\n";
               print  "${d}[POLYGON]\n";
               printf "${d}Type=%s\n",        $type[1];
               printf "${d}EndLevel=%d\n",    $type[4]              if ($type[4] > $type[3]);
               print  "${d}Label=$polyname\n"                       if ($polyname);
               printf "${d}Data%d=(%s)\n",    $type[3], join ("), (", @nodes{@chain});
               if ($mpoly{$id}) {
                   printf "; this is multipolygon with %d holes: %s\n", scalar @{$mpoly{$id}}, join (", ", @{$mpoly{$id}});
                   for my $hole (@{$mpoly{$id}}) {
                       if ($mpholes{$hole} ne $hole && @{$mpholes{$hole}}) {
                           printf "${d}Data%d=(%s)\n",    $type[3], join ("), (", @nodes{@{$mpholes{$hole}}});
                       }
                   }
               }
               print  "${d}[END]\n\n\n";
           }
       }
   }

} continue { $_ = <IN>; }

printf STDERR "%d roads loaded
                          $countlines lines and $countpolygons polygons dumped\n", scalar keys %rchain;






####    Detecting end nodes

my %enodes;
my %rstart;

while (my ($road, $pchain) = each %rchain) {
    $enodes{$pchain->[0]}  ++;
    $enodes{$pchain->[-1]} ++;
    push @{$rstart{$pchain->[0]}}, $road;
}





####    Merging roads

my %rmove;

if ($mergeroads) {
    print "\n\n\n";
    print STDERR "Merging roads...          ";

    my $countmerg = 0;
    my @keys = keys %rchain;

    my $i = 0;
    while ($i < scalar @keys) {

        my $r1 = $keys[$i];
        if ($rmove{$r1}) {      $i++;   next;   }
        my $p1 = $rchain{$r1};

        my @list = ();
        for my $r2 (@{$rstart{$p1->[-1]}}) {
            if ( $r1 ne $r2  &&  $rprops{$r2}
              && join(":",@{$rprops{$r1}})  eq  join(":",@{$rprops{$r2}})
              && $risin{$r1} eq $risin{$r2}
              && lcos($p1->[-2],$p1->[-1],$rchain{$r2}->[1]) > $mergecos ) {
                push @list, $r2
            }
        }

        if (scalar @list) {
            $countmerg ++;
            @list = sort { lcos($p1->[-2],$p1->[-1],$rchain{$b}->[1]) <=> lcos($p1->[-2],$p1->[-1],$rchain{$a}->[1]) }  @list;
            printf "; FIX: Road WayID=$r1 may be merged with %s at (%s)\n", join (", ", @list), $nodes{$p1->[-1]};

            my $r2 = $list[0];
            $rmove{$r2} = $r1;

            if ($restrictions) {
                while ( my ($relid, $tr) = each %trest )  {
                    if ( $tr->{fr_way} eq $r2 )  {  
                        print "; FIX: RelID=$relid FROM moved from WayID=$r2 to WayID=$r1\n";
                        $tr->{fr_way} = $r1;
                        $tr->{fr_pos} += ( (scalar @{$rchain{$r1}}) - 1 );
                    }
                    if ( $tr->{to_way} eq $r2 )  {  
                        print "; FIX: RelID=$relid FROM moved from WayID=$r2 to WayID=$r1\n";
                        $tr->{to_way} = $r1;
                        $tr->{to_pos} += ( (scalar @{$rchain{$r1}}) - 1 );
                    }
                }
            }

            $enodes{$rchain{$r2}->[0]} -= 2;
            push @{$rchain{$r1}}, @{$rchain{$r2}}[1..$#{$rchain{$r2}}];
            delete $rchain{$r2};
            delete $rprops{$r2};
            delete $risin{$r2};
            @{$rstart{$p1->[-1]}} = grep { $_ ne $r2 } @{$rstart{$p1->[-1]}};
        } else {
            $i ++;
        }
    }

    print STDERR "$countmerg merged\n";
}





####    Generating routing graph

my %rnodes;
my %nodid;
my %nodeways;

print STDERR "Detecting road nodes...   ";

while (my ($road, $pchain) = each %rchain) {
    for my $node (@{$pchain}) {
        $rnodes{$node} ++;
        push @{$nodeways{$node}}, $road         if ($nodetr{$node});
    }
}

my $nodcount = 1;
for my $node (keys %rnodes) {
    if ( $rnodes{$node}>1 || $enodes{$node}>0 || $xnodes{$node} || (defined($nodetr{$node}) && scalar @{$nodetr{$node}}) ) {
#        printf "; NodID=$nodcount - NodeID=$node at (%s) - $rnodes{$node} roads, $enodes{$node} ends, X=$xnodes{$node}, %d trs\n", $nodes{$node}, (defined($nodetr{$node}) && scalar @{$nodetr{$node}});
        $nodid{$node} = $nodcount++;
    }
}

printf STDERR "%d found\n", scalar keys %nodid;





####    Detecting duplicate road segments


if ($detectdupes) {

    my %segways;

    print STDERR "Detecting duplicates...   ";
    print "\n\n\n; ### Duplicate roads\n\n";

    while (my ($road, $pchain) = each %rchain) {
        for (my $i=0; $i<$#{$pchain}; $i++) {
            if ( $nodid{$pchain->[$i]} && $nodid{$pchain->[$i+1]} )   {
                push @{$segways{join(":",( sort {$a cmp $b} ($pchain->[$i],$pchain->[$i+1]) ))}}, $road;
            }
        }
    }

    my $countdupsegs  = 0;
    my $countduproads = 0;

    my %roadsegs;
    my %roadpos;

    for my $seg (keys %segways) {
        if ( $#{$segways{$seg}} > 0 ) {
            $countdupsegs ++;
            my $roads = join ", ", ( sort {$a cmp $b} @{$segways{$seg}} );
            $roadsegs{$roads} ++;
            my ($point) = split (":", $seg);
            $roadpos{$roads} = $nodes{$point};
        }
    }

    for my $road (keys %roadsegs) {
        $countduproads ++;
        printf "; ERROR: Roads $road has $roadsegs{$road} duplicate segments near ($roadpos{$road})\n";
    }

    printf STDERR "$countdupsegs segments, $countduproads roads\n";
}




####    Fixing self-intersections and long roads

if ($splitroads) {
    my $countself = 0;
    my $countlong = 0;
    print "\n\n\n";

    print STDERR "Splitting roads...        ";
    while (my ($road, $pchain) = each %rchain) {
        my $j = 0;
        my @breaks = ();
        my $break = 0;
        my $rnod = 1;
        for (my $i=1; $i < scalar @{$pchain}; $i++) {
            $rnod ++  if ( ${nodid{$pchain->[$i]}} );
            if (scalar (grep { $_ eq $pchain->[$i] } @{$pchain}[$break..$i-1]) > 0) {
                $countself ++;
#                print "; ERROR: WayID=$road has self-intersecton near (${nodes{$pchain->[$i]}})  ($i $j)\n";
                if ($pchain->[$i] ne $pchain->[$j]) {
                    $break = $j;
                    push @breaks, $break;
                } else {
                    $break = ($i + $j) >> 1;
                    push @breaks, $break;
                    $nodid{$pchain->[$break]} = $nodcount++;
                    printf "; FIX: Added NodID=%d for NodeID=%s at (%s)\n", $nodid{$pchain->[$break]}, $pchain->[$break], $nodes{$pchain->[$break]};
                }
                $rnod = 1;
            }
            if ($rnod == 60) {
                $countlong ++;
#                print "; ERROR: WayID=$road has too many nodes  ($i $j)\n";
                $break = $j;
                push @breaks, $break;
                $rnod = 1;
            }
            $j = $i             if ($nodid{$pchain->[$i]});
        }
        if (scalar @breaks > 0) {
            printf "; FIX: WayID=$road is splitted at %s\n", join (", ", @breaks);
            push @breaks, $#{$pchain};
            for (my $i=0; $i<$#breaks; $i++) {
                my $id = $road."/".($i+1);
                printf "; FIX: Added road %s, nodes from %d to %d\n", $id, $breaks[$i], $breaks[$i+1];
                $rchain{$id} = [ @{$pchain}[$breaks[$i] .. $breaks[$i+1]] ];
                $rprops{$id} = $rprops{$road};
                $risin{$id}  = $risin{$road};

                if ($restrictions) {
                    while ( my ($relid, $tr) = each %trest )  {  
                        if ( $tr->{to_way} eq $road ) {
                            #print "; Rel=$relid   ". join (" : ", %{$tr}) ."\n";
                            if ( $tr->{to_pos} > $breaks[$i]-(1+$tr->{to_dir})/2 && $tr->{to_pos} <= $breaks[$i+1]-(1+$tr->{to_dir})/2 ) {
                                $tr->{to_way} = $id;
                                $tr->{to_pos} -= $breaks[$i];
                                print "; FIX: Turn restriction RelID=$relid moved to WayID=$id\n";
                                #print "; now Rel=$relid   ". join (" : ", %{$tr}) ."\n";
                            }
                        }
                        if ( $tr->{fr_way} eq $road ) {
                            #print "; Rel=$relid   ". join (" : ", %{$tr}) ."\n";
                            if ( $tr->{fr_pos} > $breaks[$i]+($tr->{fr_dir}-1)/2 && $tr->{fr_pos} <= $breaks[$i+1]+($tr->{fr_dir}-1)/2 ) {
                                $tr->{fr_way} = $id;
                                $tr->{fr_pos} -= $breaks[$i];
                                print "; FIX: Turn restriction RelID=$relid moved to WayID=$id\n";
                                #print "; now Rel=$relid   ". join (" : ", %{$tr}) ."\n";
                            }
                        }
                    }
                }
            }
            $#{$pchain} = $breaks[0];
        }
    }
    print STDERR "$countself self-intersections, $countlong long roads\n";
}





####    Fixing "too close nodes" error

if ($fixclosenodes) {
    my $countclose = 0;

    print "\n\n\n";
    print STDERR "Fixing close nodes...     ";
    while (my ($road, $pchain) = each %rchain) {
        my $cnode = $pchain->[0];
        for my $node (@{$pchain}[1..$#{$pchain}]) {
            if ($node ne $cnode && $nodid{$node}) {
                if (closenodes($cnode, $node)) {
                    print "; ERROR: too close nodes $cnode and $node, WayID=$road near (${nodes{$node}})\n";
                    $countclose ++;
                }
                $cnode = $node;
            }
        }
    }
    print STDERR "$countclose pairs fixed\n";
}






####    Dumping roads

my %roadid;

print STDERR "Writing roads...          ";
print "\n\n\n; ### Roads\n\n";

my $roadcount = 1;
while (my ($road, $pchain) = each %rchain) {
    my ($poly, $name, $rp) = @{$rprops{$road}};
    my @type = @{$polytype{$poly}};

    $roadid{$road} = $roadcount;

    #  @type == [ $mode, $type, $prio, $llev, $hlev, $rp ]
    print  "; WayID = $road\n";
    print  "; $poly\n";
    print  "[POLYLINE]\n";
    printf "Type=%s\n",        $type[1];
    printf "EndLevel=%d\n",    $type[4]             if ($type[4] > $type[3]);
    print  "Label=$name\n"                          if ($name);
    print  "DirIndicator=1\n"                       if ((split /\,/, $rp)[2]);

    print  "; is_in = $risin{$road}\n"  if ($risin{$road});
    my ($city, $region, $country) = split (/,/, $risin{$road});

    printf "CityName=%s\n", $city ? $city : $defaultcity;
    print  "RegionName=$region\n"       if ($region);
    print  "CountryName=$country\n"     if ($country);

    printf "Data%d=(%s)\n", $type[3], join ("), (", @nodes{@{$pchain}});
    printf "RoadID=%d\n", $roadcount++;
    printf "RouteParams=%s\n", $rp;

    my $nodcount=0;
    for (my $i=0; $i < scalar @{$pchain}; $i++) {
        my $node = $pchain->[$i];
        if ($nodid{$node}) {
            printf "Nod%d=%d,%d,%d\n", $nodcount++, $i, $nodid{$node}, $xnodes{$node};
        }
    }

    print  "[END]\n\n\n";
}

printf STDERR "%d written\n", $roadcount-1;





####    Writing turn restrictions

my $counttrest = 0;
if ($restrictions) {

    print "\n\n\n; ### Turn restrictions\n\n";

    print STDERR "Writing restrictions...   ";

    while ( my ($relid, $tr) = each %trest ) {

        print  "\n; Rel=$relid    ". join (" : ", %{$tr}) ."\n";
        my $err = 0;

        if  ($tr->{fr_dir} == 0)        {  $err=1;  print "; ERROR: RelID=$relid FROM road does'n have VIA end node\n";  }
        if  ($tr->{to_dir} == 0)        {  $err=1;  print "; ERROR: RelID=$relid TO road does'n have VIA end node\n"; } 

        if ( !$err && $tr->{type} eq "no") {
            dumptrest ($tr);
        }

        if ( !$err && $tr->{type} eq "only") {
#            print  "; Roads:  " . join (", ", @{$nodeways{$trest{$relid}->{node}}}) . "\n";
            my %newtr = (
                    node    => $tr->{node},
                    fr_way  => $tr->{fr_way},
                    fr_dir  => $tr->{fr_dir},
                    fr_pos  => $tr->{fr_pos}
                );
            for my $road (@{$nodeways{$trest{$relid}->{node}}}) {
                print "; To road $road \n";
                $newtr{to_way} = $road;
                $newtr{to_pos} = indexof( $rchain{$road}, $tr->{node} );

                if ( $newtr{to_pos} > 0 && !($tr->{to_way} eq $road && $tr->{to_dir} eq -1) ) {
                    $newtr{to_dir} = -1;
                    dumptrest (\%newtr);
                }
                if ( $newtr{to_pos} < $#{$rchain{$road}} && !($tr->{to_way} eq $road && $tr->{to_dir} eq 1) ) {
                    $newtr{to_dir} = 1;
                    dumptrest (\%newtr);
                }
            }
        }
    }

    print STDERR "$counttrest written\n";
}





print STDERR "All done!!\n\n";








####    Functions

use Encode;

sub convert_string {            # String

   my $str = decode("utf8", $_[0]);
   $str = uc($str) if ($upcase);
   $str = $nocodepage ? $_[0] : encode ("cp".$codepage, $str);

   $str =~ s/\&amp\;/\&/gi;
   $str =~ s/\&#38\;/\&/gi;
   $str =~ s/\&quot\;/\"/gi;
   $str =~ s/\&apos\;/\'/gi;
   $str =~ s/\&#39\;/\'/gi;
   $str =~ s/\&#47\;/\//gi;
   $str =~ s/\&#92\;/\\/gi;
   $str =~ s/\&#13\;/-/gi;

   $str =~ s/\&#\d+\;/_/gi;

   return $str;
}



sub closenodes {                # NodeID1, NodeID2

    my ($lat1, $lon1) = split ",", $nodes{$_[0]};
    my ($lat2, $lon2) = split ",", $nodes{$_[1]};

    my ($clat, $clon) = ( ($lat1+$lat2)/2, ($lon1+$lon2)/2 );
    my ($dlat, $dlon) = ( ($lat2-$lat1), ($lon2-$lon1) );
    my $klon = cos ($clat*3.14159/180);

    my $ldist = $fixclosedist * 180 / 20_000_000;

    my $res = ($dlat**2 + ($dlon*$klon)**2) < $ldist**2;

    # fixing
    if ($res) {
        if ($dlon == 0) {
            $nodes{$_[0]} = ($clat - $ldist/2 * ($dlat==0 ? 1 : ($dlat <=> 0) )) . "," . $clon;
            $nodes{$_[1]} = ($clat + $ldist/2 * ($dlat==0 ? 1 : ($dlat <=> 0) )) . "," . $clon;
        } else {
            my $azim = $dlat / $dlon;
            my $ndlon = sqrt ($ldist**2 / ($klon**2 + $azim**2)) / 2;
            my $ndlat = $ndlon * abs($azim);

            $nodes{$_[0]} = ($clat - $ndlat * ($dlat <=> 0)) . "," . ($clon - $ndlon * ($dlon <=> 0));
            $nodes{$_[1]} = ($clat + $ndlat * ($dlat <=> 0)) . "," . ($clon + $ndlon * ($dlon <=> 0));
        }
    }
    return $res;
}



sub lcos {                      # NodeID1, NodeID2, NodeID3

    my ($lat1, $lon1) = split ",", $nodes{$_[0]};
    my ($lat2, $lon2) = split ",", $nodes{$_[1]};
    my ($lat3, $lon3) = split ",", $nodes{$_[2]};

    my $klon = cos (($lat1+$lat2+$lat3)/3*3.14159/180);

    my $xx = (($lat2-$lat1)**2+($lon2-$lon1)**2*$klon**2)*(($lat3-$lat2)**2+($lon3-$lon2)**2*$klon**2);
    return -1   if ( $xx == 0);
    return (($lat2-$lat1)*($lat3-$lat2)+($lon2-$lon1)*($lon3-$lon2)*$klon**2) / sqrt ($xx);
}



sub indexof {                   # \@array, $elem

    for (my $i=0; $i < scalar @{$_[0]}; $i++)
        { return $i if ($_[0]->[$i] eq $_[1]); }
    return -1;
}


sub speedcode {                 # $speed
    return 7            if ($_[0] > 110);
    return 6            if ($_[0] > 90);
    return 5            if ($_[0] > 80);
    return 4            if ($_[0] > 60);
    return 3            if ($_[0] > 40);
    return 2            if ($_[0] > 20);
    return 1            if ($_[0] > 10);
    return 0;
}


sub insidebbox {                # $latlon

    my ($lat, $lon) = split /,/, $_[0];
    return 1    if ( $lat>=$minlat && $lon>=$minlon && $lat<$maxlat && $lon<$maxlon );
    return 0;

}


sub dumptrest {                 # \%trest

    $counttrest ++;

    my $tr = $_[0];

    my $i = $tr->{fr_pos} - $tr->{fr_dir};
    $i -= $tr->{fr_dir}         while ( !$nodid{$rchain{$tr->{fr_way}}->[$i]} && $i>=0 && $i < $#{$rchain{$tr->{fr_way}}} );
    my $j = $tr->{to_pos} + $tr->{to_dir};
    $j += $tr->{to_dir}         while ( !$nodid{$rchain{$tr->{to_way}}->[$j]} && $j>=0 && $j < $#{$rchain{$tr->{to_way}}} );

    print  "[Restrict]\n";
    printf "Nod=${nodid{$tr->{node}}}\n";
    print  "TraffPoints=${nodid{$rchain{$tr->{fr_way}}->[$i]}},${nodid{$tr->{node}}},${nodid{$rchain{$tr->{to_way}}->[$j]}}\n";
    print  "TraffRoads=${roadid{$tr->{fr_way}}},${roadid{$tr->{to_way}}}\n";
    print  "Time=\n";
    print  "[END-Restrict]\n\n";
}

