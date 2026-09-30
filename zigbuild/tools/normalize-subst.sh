#!/usr/bin/env bash
# Normalize the entries of a vendored subst.txt that record what the
# capturing machine happened to have installed rather than anything about
# R or the platform (feat-no-host-paths PLAN.md, phase A1). With them
# fixed, two captures of the same platform and variant are identical
# wherever they run, so a difference means a real change.
#
# Usage: normalize-subst.sh <macos|linux> <subst.txt>   (edits in place)
# gen-subst.sh runs it on every capture; it is idempotent.
#
#   blank   LD (libtool's own checks), TEXI2ANY, TEXI2ANY_VERSION_MAJ/MIN,
#           INSTALL_INFO (doc/manual only), TEXI2DVI: tools for building
#           the manuals or configure internals, which zig build never
#           uses. Found by path on some machines only (GitHub's arm64
#           runner has texinfo; the dev machine has conda's ld).
#   fixed   NM "nm -B" (Makeconf; bare, found on PATH like every tier-3
#           tool), TEXI2DVICMD "texi2dvi", YACC "yacc", ACLOCAL/AUTOCONF/
#           AUTOHEADER as configure's `missing` wrapper (the value when
#           autotools are absent), PAGER "less", R_BROWSER/R_PDFVIEWER
#           the desktop opener (xdg-open, or open on macOS). stage.sh
#           sets the same Renviron defaults; recording them here keeps
#           capture paths such as /usr/bin/firefox out of the configs.
set -euo pipefail
os="${1:?usage: normalize-subst.sh <macos|linux> <subst.txt>}"
f="${2:?usage: normalize-subst.sh <macos|linux> <subst.txt>}"
case "$os" in macos) opener=open ;; *) opener=xdg-open ;; esac

missing='$(SHELL) \\"$(abs_top_srcdir)/tools/missing\\"'
sed -i \
  -e 's|^S\["LD"\]=".*"$|S["LD"]=""|' \
  -e 's|^S\["TEXI2ANY"\]=".*"$|S["TEXI2ANY"]=""|' \
  -e 's|^S\["TEXI2ANY_VERSION_MAJ"\]=".*"$|S["TEXI2ANY_VERSION_MAJ"]=""|' \
  -e 's|^S\["TEXI2ANY_VERSION_MIN"\]=".*"$|S["TEXI2ANY_VERSION_MIN"]=""|' \
  -e 's|^S\["INSTALL_INFO"\]=".*"$|S["INSTALL_INFO"]=""|' \
  -e 's|^S\["TEXI2DVI"\]=".*"$|S["TEXI2DVI"]=""|' \
  -e 's|^S\["NM"\]=".*"$|S["NM"]="nm -B"|' \
  -e 's|^S\["TEXI2DVICMD"\]=".*"$|S["TEXI2DVICMD"]="texi2dvi"|' \
  -e 's|^S\["YACC"\]=".*"$|S["YACC"]="yacc"|' \
  -e "s|^S\\[\"ACLOCAL\"\\]=\".*\"\$|S[\"ACLOCAL\"]=\"$missing aclocal\"|" \
  -e "s|^S\\[\"AUTOCONF\"\\]=\".*\"\$|S[\"AUTOCONF\"]=\"$missing autoconf\"|" \
  -e "s|^S\\[\"AUTOHEADER\"\\]=\".*\"\$|S[\"AUTOHEADER\"]=\"$missing autoheader\"|" \
  -e 's|^S\["PAGER"\]=".*"$|S["PAGER"]="less"|' \
  -e "s|^S\\[\"R_BROWSER\"\\]=\".*\"\$|S[\"R_BROWSER\"]=\"$opener\"|" \
  -e "s|^S\\[\"R_PDFVIEWER\"\\]=\".*\"\$|S[\"R_PDFVIEWER\"]=\"$opener\"|" \
  "$f"
