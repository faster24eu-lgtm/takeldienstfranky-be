# takeldienstfranky.be

Static site, built with Perl (no dependencies):

    perl _build/build.pl

Pages live in `_build/pages/*.page` (format documented at the top of `build.pl`).
The builder writes the HTML next to this folder, plus `sitemap.xml` and `robots.txt`.

- `$PREVIEW = 1` in `build.pl` puts noindex on every page and blocks robots.txt.
  Set it to 0 only when the site runs on takeldienstfranky.be.
- The old Wix URLs are kept: /depannages-takeldienst/, /verhuur-autos/,
  /contacteer-ons/, /privacy-policy/.
- The contact form posts to formsubmit.co. The first submission sends an
  activation e-mail to franky.slock@skynet.be that must be confirmed once.
- Photos come from the old Wix site (Franky's own photos).
