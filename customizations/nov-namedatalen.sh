#!/bin/bash
patch -p0 << "EOF"
--- src/include/pg_config_manual.h  2019-08-19 20:30:13.601458061 +0200
+++ src/include/pg_config_manual.h  2019-08-19 20:30:33.665467170 +0200
@@ -26,7 +26,7 @@
  *
  * Changing this requires an initdb.
  */
-#define NAMEDATALEN 64
+#define NAMEDATALEN 256
 
 /*
  * Maximum number of arguments to a function.

--- debian/rules   2019-08-07 09:36:28.000000000 +0000
+++ debian/rules   2019-08-20 06:41:00.365046658 +0000
@@ -48,4 +48,5 @@
 endif
 
+CFLAGS+= -DNAMEDATALEN=256
 COMMON_CONFIGURE_FLAGS= \
   --mandir=/usr/share/postgresql/\$(MAJOR_VER)/man \
@@ -58,5 +59,5 @@
   --libexecdir=/usr/lib/postgresql/ \
   --includedir=/usr/include/postgresql/ \
-  --with-extra-version=" ($(DEB_VENDOR) $(DEB_VERSION))" \
+  --with-extra-version=" ($(DEB_VENDOR) $(DEB_VERSION)) - Customized with longer NAMEDATALEN" \
   --enable-nls \
   --enable-integer-datetimes \
EOF

# Update the changelog to ensure we can identify the package
DEBFULLNAME="Timescale" DEBEMAIL="support@timescale.com" dch --local=nov "NAMEDATALEN set to 256"