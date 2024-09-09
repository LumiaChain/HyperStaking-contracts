#!/usr/bin/env bash

CSS=css/markdown.css

# Generate PDF from markdown
# $1: markdown filename
# $2: pdf filename
function generate_pdf {
  local temp_html="spec.temp.html"

  pandoc --css $CSS -s -f markdown+smart --metadata pagetitle="Lumia Smart Contracts" --to=html5 $1 -o $temp_html
  wkhtmltopdf  --page-size A4 --margin-top 5 --margin-bottom 5 --enable-local-file-access  $temp_html $2

  rm $temp_html
}

generate_pdf README.md spec.pdf
