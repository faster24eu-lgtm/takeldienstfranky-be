#!/usr/bin/perl
# Site builder for takeldienstfranky.be
#
#   perl _build/build.pl
#
# Reads every _build/pages/**/*.page file and writes the matching page:
#   index.page                  -> index.html
#   404.page                    -> 404.html
#   takeldienst-eeklo.page      -> takeldienst-eeklo/index.html
# wrapped in the shared head, header, footer and scripts.
# Also writes sitemap.xml and robots.txt, and reports broken internal links,
# long titles and pages without exactly one <h1>.
#
# .page format: "key: value" lines, then sections that start with a line
# "===NAME===". Every section becomes a field (lower case name).
#   title, description   meta tags
#   h1, h1b               heading; h1b is the second (white) line (optional)
#   label                 breadcrumb label and link text in lists
#   kind                  regio | dienst  (used by {{LIST:kind}} and the footer)
#   card                  one-line summary for lists
#   img, imgalt           page head photo (assets/img/...)
#   template              page | raw   (raw: MAIN is the whole <main>)
#   order                 sort order in lists
#   sitemap: no           leave out of sitemap
# Sections: LEAD (intro under the h1), MAIN, FAQ ("V: ..." / "A: ..." lines).
#
# Placeholders: {{R}} {{PHONE}} {{PHONE_HREF}} {{WA_HREF}} {{EMAIL}}
# {{FORM}} {{GALLERY}} {{FLEET}} {{CTA}} {{VACATURE}} {{LIST:kind}}
use strict;
use warnings;
use utf8;
use File::Find;
use File::Path qw(make_path);
use File::Basename qw(dirname);
binmode STDOUT, ":encoding(UTF-8)";

# ---------------------------------------------------------------- settings
# PREVIEW = 1: every page gets noindex and robots.txt blocks crawling.
# Set to 0 only when the site runs on its own domain and is ready to launch.
my $PREVIEW   = 1;
my $BASE      = 'https://takeldienstfranky.be';
my $NAME      = 'Takeldienst Franky';
my $PHONE      = '+32 3 375 67 37';     # same number as takeldienstfaster.be
my $PHONE_HREF = 'tel:+3233756737';
my $WA_HREF    = 'https://wa.me/3233756737?text=Hallo%2C%20ik%20heb%20een%20takeldienst%20nodig.%20Mijn%20locatie%3A%20';
my $EMAIL     = 'franky.slock@skynet.be';
my $FORM_TO   = $EMAIL;                 # formsubmit.co: first submission sends an activation mail
my $VAT       = 'BE0539825091';
my $FACEBOOK  = 'https://www.facebook.com/takeldienstfranky.be/';
my $MAPS_HQ   = 'https://www.google.com/maps/search/?api=1&query=Eeklostraat+63+9971+Lembeke';
my $MAPS_DEP  = 'https://www.google.com/maps/search/?api=1&query=Oostmoer+129A+9950+Lievegem';

my @NAV = (
  ['Home',                   ''],
  ['Depannage &amp; takelen', 'depannages-takeldienst/'],
  ['Vervangwagens',          'verhuur-autos/'],
  ['Regio',                  'regio/'],
  ['Vacature',               'vacature/'],
  ['Contact',                'contacteer-ons/'],
);

# ---------------------------------------------------------------- read pages
my $root = dirname(dirname(__FILE__));
chdir $root or die "chdir $root: $!";

my %P;
find(sub {
  return unless /\.page$/;
  my $src = $File::Find::name;
  (my $rel = $src) =~ s{^_build/pages/}{};
  $rel =~ s/\.page$//;
  my $out = $rel eq 'index' ? 'index.html'
          : $rel eq '404'   ? '404.html'
          : "$rel/index.html";
  (my $url = $out) =~ s{index\.html$}{};
  open my $fh, '<:encoding(UTF-8)', $_ or die "$src: $!";
  local $/; my $t = <$fh>; close $fh;
  $t =~ s/\r\n/\n/g;
  my @parts = split /^===([A-Z]+)===\n/m, $t;
  my %p = (src => $src, out => $out, url => $url);
  for (split /\n/, shift @parts) { $p{$1} = $2 if /^(\w+):\s*(.*?)\s*$/ }
  while (@parts) { my ($k, $v) = splice @parts, 0, 2; $v //= ""; $v =~ s/\s+$//; $p{lc $k} = $v }
  $p{template} //= 'page';
  for (qw(title description label)) { warn "$src: no $_\n" unless $p{$_} }
  $P{$out} = \%p;
}, '_build/pages');

# ---------------------------------------------------------------- helpers
sub esc { my $s = shift // ''; $s =~ s/&(?!\w+;|#\d+;)/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
sub jstr { my $s = shift // ''; $s =~ s/<[^>]+>//g; $s =~ s/&nbsp;/ /g; $s =~ s/&amp;/&/g; $s =~ s/&rsquo;/’/g; $s =~ s/&euml;/ë/g; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\n/ /g; $s }
sub kind_pages { my $k = shift; sort { ($a->{order} // 50) <=> ($b->{order} // 50) || $a->{label} cmp $b->{label} } grep { ($_->{kind} // '') eq $k } values %P }

sub faq_items {
  my $f = shift // return ();
  my @out; my ($q, $a);
  for my $line (split /\n/, $f) {
    if ($line =~ /^V:\s*(.*)/) { push @out, [$q, $a] if $q; ($q, $a) = ($1, '') }
    elsif ($line =~ /^A:\s*(.*)/) { $a = $1 }
    elsif ($line =~ /\S/ && defined $a) { $a .= " $line" }
  }
  push @out, [$q, $a] if $q;
  @out;
}

sub faq_html {
  my @f = @_;
  return '' unless @f;
  my $h = qq{<section class="section"><div class="container narrow"><span class="eyebrow">Veelgestelde vragen</span><h2>Goed om te weten</h2><div class="faq">};
  $h .= qq{<details><summary>$_->[0]</summary><div class="faq-a"><p>$_->[1]</p></div></details>} for @f;
  $h . '</div></div></section>';
}

sub list_html {
  my $kind = shift;
  my $h = qq{<div class="card-grid">};
  for (kind_pages($kind)) {
    my $img = $_->{img} ? qq{<img src="{{R}}assets/img/$_->{img}" alt="" width="480" height="358" loading="lazy">} : '';
    $h .= qq{<a class="card" href="{{R}}$_->{url}">$img<div class="card-body"><h3>$_->{label}</h3><p>} . ($_->{card} // '') . qq{</p><span class="more">Meer info &rarr;</span></div></a>};
  }
  "$h</div>";
}

my $CALL_BTNS = qq{<a class="btn btn-wa" href="{{WA_HREF}}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.3-.4.2-.4.7-1.4.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c1.7.7 2.3.8 3.2.6.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.1-.3-.2-.5-.3z"/></svg> WhatsApp</a><a class="btn btn-yellow" href="{{PHONE_HREF}}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1A17 17 0 0 1 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z"/></svg> {{PHONE}}</a>};

sub form_html {
  return <<"H";
<form class="form" action="https://formsubmit.co/$FORM_TO" method="POST">
<input type="hidden" name="_subject" value="Aanvraag via takeldienstfranky.be">
<input type="hidden" name="_next" value="$BASE/bedankt/">
<input type="hidden" name="_template" value="table">
<input type="text" name="_honey" class="hp" tabindex="-1" autocomplete="off" aria-hidden="true">
<div class="form-row"><label>Naam*<input name="naam" required autocomplete="name"></label><label>Telefoonnummer*<input name="telefoon" type="tel" required autocomplete="tel"></label></div>
<label>E-mail*<input name="email" type="email" required autocomplete="email"></label>
<label>Waar staat het voertuig?<input name="locatie" placeholder="Adres of plaats"></label>
<label>Opmerking*<textarea name="opmerking" rows="4" required placeholder="Wat is er gebeurd, welk voertuig, waar moet het naartoe?"></textarea></label>
<button class="btn btn-yellow btn-block" type="submit">Verstuur</button>
<p class="form-note">Dringend? Bel ons rechtstreeks, dat gaat sneller dan het formulier.</p>
</form>
H
}

my @GALLERY = (
  ['takeldienst-franky-takelwagen-eeklo.jpg', 'Gele takelwagen van Takeldienst Franky voor het bord met de telefoonnummers in Eeklo', 960, 960],
  ['kraanwagen-tilt-mercedes.jpg',            'Kraanwagen van Takeldienst Franky tilt een grijze Mercedes op met een hefbrug', 960, 716],
  ['oldtimer-op-plateau.jpg',                 'Groene oldtimer vastgesjord op het gele plateau van Takeldienst Franky', 600, 800],
  ['bergingswagen-takelarm.jpg',              'Gele bergingswagen van Takeldienst Franky met de takelarm uitgeklapt', 960, 716],
  ['pickup-met-aanhangwagen.jpg',             'Rode pick-up van Takeldienst Franky met een auto op de aanhangwagen', 1000, 750],
  ['plateauwagen-franky.jpg',                 'Plateauwagen van Takeldienst Franky in het depot', 600, 800],
  ['mercedes-op-kraanwagen.jpg',              'Mercedes veilig op de kraanwagen van Takeldienst Franky gezet', 960, 716],
  ['bergingswagen-takelarm-bedienen.jpg',     'Chauffeur van Takeldienst Franky bedient de takelarm van de bergingswagen', 1000, 748],
);
sub gallery_html {
  my $h = qq{<section class="section grey"><div class="container"><div class="section-head"><div><span class="eyebrow">Ons werk</span><h2>Eigen takelwagens, echte opdrachten</h2></div><p>Geen stockfoto&rsquo;s: dit is het materieel van Takeldienst Franky aan het werk.</p></div><div class="gallery">};
  $h .= qq{<figure><img src="{{R}}assets/img/$_->[0]" alt="$_->[1]" width="$_->[2]" height="$_->[3]" loading="lazy"></figure>} for @GALLERY;
  $h . '</div></div></section>';
}

my $FLEET = <<'H';
<div class="fleet">
<div><strong>Takelwagens</strong><span>Voor auto&rsquo;s die niet meer kunnen rijden: opladen en weg.</span></div>
<div><strong>Kraanwagen</strong><span>Met een kraan tillen we een voertuig op, ook waar een takelwagen er niet bij kan.</span></div>
<div><strong>Bergingswagen</strong><span>Met takelarm voor zwaardere voertuigen en lastige bergingen.</span></div>
<div><strong>Plateauwagens</strong><span>Voor moto&rsquo;s, oldtimers en lichte vracht die u liever niet laat slepen.</span></div>
</div>
H

my $CTA = <<'H';
<section class="cta-band"><div class="container cta-inner"><h2>Bel Takeldienst Franky om uw auto te laten takelen in gans Belgi&euml;. Wij zorgen voor elke depannage!</h2><div class="cta-actions">CALLBTNS</div></div></section>
H
$CTA =~ s/CALLBTNS/$CALL_BTNS/;

my $VACATURE = <<'H';
<section class="section"><div class="container"><div class="vacature">
<div><span class="eyebrow">Vacature</span><h2>Chauffeur gezocht</h2><p class="big">We zijn op zoek naar een gemotiveerde chauffeur met rijbewijs C of CE met code 95 en kennis van automechanica.</p><p>Interesse? Neem zeker contact met ons op. <a href="{{R}}vacature/">Lees meer over de vacature</a>.</p></div>
<div class="vac-actions"><a class="btn btn-white" href="{{PHONE_HREF}}">Bel {{PHONE}}</a><a class="btn btn-white" href="{{WA_HREF}}">WhatsApp</a></div>
</div></div></section>
H

# ---------------------------------------------------------------- templates
sub page_main {
  my $p = shift;
  my $lead = $p->{lead} ? qq{<div class="lead">$p->{lead}</div>} : '';
  my $h1b = $p->{h1b} ? qq{ <span>$p->{h1b}</span>} : '';
  my $media = $p->{img} ? qq{<figure class="head-media"><img src="{{R}}assets/img/$p->{img}" alt="} . esc($p->{imgalt} // '') . qq{" width="960" height="716" loading="eager" fetchpriority="high"></figure>} : '';
  my $cls = $media ? ' has-media' : '';
  return <<"H";
<section class="page-head$cls"><div class="container head-grid"><div><h1>$p->{h1}$h1b</h1>$lead<div class="actions">$CALL_BTNS</div></div>$media</div></section>
$p->{main}
H
}

sub crumbs {
  my $p = shift;
  return ('', '') if $p->{url} eq '' || $p->{out} eq '404.html';
  my @c = (['Home', '']);
  push @c, ['Regio', 'regio/'] if ($p->{kind} // '') eq 'regio';
  push @c, [$p->{label}, $p->{url}];
  my $html = '<nav class="crumbs container" aria-label="Kruimelpad">' . join(' <span>/</span> ', map { $_ == $#c ? "<span>$c[$_][0]</span>" : qq{<a href="{{R}}$c[$_][1]">$c[$_][0]</a>} } 0..$#c) . '</nav>';
  my $i = 0;
  my $ld = '{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[' . join(',', map { $i++; qq{{"\@type":"ListItem","position":$i,"name":"} . jstr($_->[0]) . qq{","item":"$BASE/$_->[1]"}} } @c) . ']}';
  return ($html, qq{<script type="application/ld+json">$ld</script>});
}

sub business_ld {
  my @area = map { qq{{"\@type":"City","name":"$_"}} } qw(Eeklo Kaprijke Lievegem Evergem Maldegem Gent);
  my $area = join ',', @area, '{"@type":"Country","name":"België"}';
  return qq{<script type="application/ld+json">{"\@context":"https://schema.org","\@type":"AutomotiveBusiness","\@id":"$BASE/#bedrijf","name":"$NAME","url":"$BASE/","logo":"$BASE/assets/img/logo-takeldienst-franky.png","image":"$BASE/assets/img/takeldienst-franky-takelwagen-eeklo.jpg","telephone":"+3233756737","email":"$EMAIL","vatID":"$VAT","address":{"\@type":"PostalAddress","streetAddress":"Eeklostraat 63","postalCode":"9971","addressLocality":"Lembeke (Kaprijke)","addressCountry":"BE"},"geo":{"\@type":"GeoCoordinates","latitude":51.1854255,"longitude":3.6171895},"contactPoint":{"\@type":"ContactPoint","telephone":"+3233756737","contactType":"customer service","areaServed":"BE","availableLanguage":"nl"},"department":{"\@type":"AutomotiveBusiness","name":"$NAME – depot Lievegem","telephone":"+3233756737","address":{"\@type":"PostalAddress","streetAddress":"Oostmoer 129A","postalCode":"9950","addressLocality":"Lievegem (Waarschoot)","addressCountry":"BE"}},"areaServed":[$area],"sameAs":["$FACEBOOK"]}</script>};
}

my $LOGO = '<a class="brand" href="{{R}}" aria-label="Takeldienst Franky, naar de homepage"><img src="{{R}}assets/img/logo-takeldienst-franky.png" alt="Takeldienst Franky Eeklo - Lievegem" width="126" height="67"></a>';

my $year = 1900 + (localtime)[5];
my @written;
for my $out (sort keys %P) {
  my $p = $P{$out};
  my $depth = () = $out =~ m{/}g;
  my $R = $out eq '404.html' ? '/' : '../' x $depth;

  my $main = $p->{template} eq 'raw' ? $p->{main} : page_main($p);
  my @faq = faq_items($p->{faq});
  $main .= faq_html(@faq);
  $main .= $CTA unless ($p->{cta} // '') eq 'no';

  my ($crumb_html, $crumb_ld) = crumbs($p);
  my $faq_ld = @faq ? '<script type="application/ld+json">{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . join(',', map { qq{{"\@type":"Question","name":"} . jstr($_->[0]) . qq{","acceptedAnswer":{"\@type":"Answer","text":"} . jstr($_->[1]) . qq{"}}} } @faq) . ']}</script>' : '';
  my $biz = ($p->{url} eq '' || $p->{url} eq 'contacteer-ons/') ? business_ld() : '';
  my $robots = $PREVIEW || ($p->{robots} // '') eq 'noindex' ? '<meta name="robots" content="noindex, nofollow">' : '';
  my $canon = "$BASE/$p->{url}";
  my $title = esc($p->{title});
  my $desc = esc($p->{description});
  my $ogimg = "$BASE/assets/img/" . ($p->{img} // 'takeldienst-franky-takelwagen-eeklo.jpg');
  my $nav = join '', map { my $cur = $p->{url} eq $_->[1] || ($_->[1] eq 'regio/' && ($p->{kind} // '') eq 'regio') ? ' aria-current="page"' : ''; qq{<a href="{{R}}$_->[1]"$cur>$_->[0]</a>} } @NAV;
  my $foot_regio = join '', map { qq{<a href="{{R}}$_->{url}">$_->{label}</a>} } kind_pages('regio');

  my $html = <<"H";
<!doctype html>
<html lang="nl-BE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="$desc">
$robots
<link rel="canonical" href="$canon">
<meta name="theme-color" content="#1a5bc4">
<meta property="og:type" content="website">
<meta property="og:locale" content="nl_BE">
<meta property="og:site_name" content="$NAME">
<meta property="og:title" content="$title">
<meta property="og:description" content="$desc">
<meta property="og:url" content="$canon">
<meta property="og:image" content="$ogimg">
<link rel="icon" href="{{R}}favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700;800;900&family=Open+Sans:wght@400;600;700&display=swap">
<link rel="stylesheet" href="{{R}}assets/css/styles.css">
$biz$crumb_ld$faq_ld
</head>
<body>
<header class="site-header">
<div class="container header-top">
$LOGO
<p class="header-claim">Bel meteen Takeldienst Franky</p>
<div class="header-actions">$CALL_BTNS</div>
<button class="menu-toggle" type="button" aria-controls="main-nav" aria-expanded="false"><span></span><span class="sr">Menu</span></button>
</div>
<nav class="main-nav" id="main-nav" aria-label="Hoofdmenu"><div class="container">$nav</div></nav>
</header>
$crumb_html
<main>
$main
</main>
<footer class="site-footer"><div class="container footer-grid">
<div><h3>$NAME</h3><p>Takelen en depanneren van auto&rsquo;s, moto&rsquo;s en lichte vracht in Vlaanderen en Walloni&euml;. Al meer dan 30 jaar.</p><p><a class="btn btn-white btn-small" href="{{R}}contacteer-ons/">Contacteer ons</a> <a class="btn btn-ghost btn-small" href="$MAPS_HQ" rel="noopener">Bereken route</a></p></div>
<div><h3>Adres</h3><p>Eeklostraat 63<br>9971 Lembeke</p><p><b>Depot</b><br>Oostmoer 129A<br>9950 Lievegem</p></div>
<div><h3>Contact</h3><p>Telefoon: <a href="{{PHONE_HREF}}">{{PHONE}}</a><br>WhatsApp: <a href="{{WA_HREF}}">stuur een bericht</a><br>E-mail: <a href="mailto:{{EMAIL}}">{{EMAIL}}</a></p><p>Ondernemingsnr.: $VAT</p><p><a href="$FACEBOOK" rel="noopener">Volg ons op Facebook</a></p></div>
<div><h3>Regio</h3>$foot_regio<a href="{{R}}regio/">Alle gemeenten</a></div>
</div><div class="container footer-bottom"><span>&copy; $year $NAME</span><span><a href="{{R}}privacy-policy/">Privacybeleid</a> &middot; <a href="{{R}}sitemap.xml">Sitemap</a></span></div></footer>
<div class="mobile-bar"><a class="wa" href="{{WA_HREF}}">Stuur een<b>WhatsApp</b></a><a href="{{PHONE_HREF}}">Bel nu<b>{{PHONE}}</b></a></div>
<script src="{{R}}assets/js/main.js" defer></script>
</body>
</html>
H

  for (1..3) {
    $html =~ s/\{\{LIST:(\w+)\}\}/list_html($1)/ge;
    $html =~ s/\{\{GALLERY\}\}/gallery_html()/ge;
    $html =~ s/\{\{FLEET\}\}/$FLEET/g;
    $html =~ s/\{\{VACATURE\}\}/$VACATURE/g;
    $html =~ s/\{\{CTA\}\}/$CTA/g;
    $html =~ s/\{\{CALLBTNS\}\}/$CALL_BTNS/g;
    $html =~ s/\{\{FORM\}\}/form_html()/ge;
  }
  $html =~ s/\{\{R\}\}/$R/g;
  $html =~ s/\{\{PHONE_HREF\}\}/$PHONE_HREF/g;
  $html =~ s/\{\{PHONE\}\}/$PHONE/g;
  $html =~ s/\{\{WA_HREF\}\}/$WA_HREF/g;
  $html =~ s/\{\{EMAIL\}\}/$EMAIL/g;
  $html =~ s/\n{2,}/\n/g;
  warn "$p->{src}: unreplaced $1\n" while $html =~ /(\{\{[A-Z_:a-z0-9]+\}\})/g;

  make_path(dirname($out)) if $out =~ m{/};
  open my $fh, '>:encoding(UTF-8)', $out or die "$out: $!";
  print $fh $html; close $fh;
  push @written, $out;
}

# ---------------------------------------------------------------- sitemap, robots
open my $sm, '>:encoding(UTF-8)', 'sitemap.xml' or die;
print $sm qq{<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
for my $p (sort { $a->{url} cmp $b->{url} } values %P) {
  next if $p->{out} eq '404.html' || ($p->{sitemap} // '') eq 'no';
  print $sm "  <url><loc>$BASE/$p->{url}</loc></url>\n";
}
print $sm "</urlset>\n"; close $sm;

open my $rb, '>', 'robots.txt' or die;
print $rb $PREVIEW ? "User-agent: *\nDisallow: /\n" : "User-agent: *\nAllow: /\n\nSitemap: $BASE/sitemap.xml\n";
close $rb;

# ---------------------------------------------------------------- checks
my $bad = 0;
for my $out (@written) {
  open my $fh, '<:encoding(UTF-8)', $out or die; local $/; my $h = <$fh>; close $fh;
  my $dir = $out =~ m{^(.*)/} ? "$1/" : '';
  while ($h =~ /(?:href|src)="([^"#?]*)/g) {
    my $l = $1;
    next if $l eq '' || $l =~ m{^(https?:|mailto:|tel:|//)};
    my $t = $l =~ m{^/} ? substr($l, 1) : "$dir$l";
    1 while $t =~ s{(^|/)(?!\.\./)[^/]+/\.\./}{$1};
    $t .= 'index.html' if $t eq '' || $t =~ m{/$};
    unless (-e $t) { print "BROKEN in $out: $l\n"; $bad++ }
  }
  my ($t) = $h =~ m{<title>(.*?)</title>}; $t =~ s/&amp;/&/g;
  printf "LONG TITLE (%d) %s: %s\n", length $t, $out, $t if length($t) > 65;
  my ($d) = $h =~ m{<meta name="description" content="(.*?)">}; $d =~ s/&amp;/&/g;
  printf "LONG DESC (%d) %s\n", length $d, $out if length($d) > 160;
  print "H1 COUNT in $out\n" if (() = $h =~ /<h1/g) != 1;
}
printf "%d pages, %d broken links%s\n", scalar @written, $bad, $PREVIEW ? ' (PREVIEW: noindex on)' : '';
