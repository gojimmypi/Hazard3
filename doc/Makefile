TOP=hazard3

.PHONY: all clean view spell

all: spell $(TOP).pdf

# `xdg-open` for Ubuntu and friends; `open` for MacOS
view: all
ifneq (,$(shell which xdg-open))
	xdg-open $(TOP).pdf
else
	open $(TOP).pdf
endif

clean:
	rm -f $(TOP).pdf

spell:
ifeq (,$(shell which codespell))
	@echo "Install codespell to check spelling"
else
	@find -name "*.adoc" | xargs codespell -L hart
	@echo "No spelling errors found"
endif

$(TOP).pdf: $(shell find -name "*.adoc" | grep -v rev.adoc) diagrams/* *.yml
	@echo ":revdate: Updated: `date +%Y-%b-%d`" > rev.adoc
	asciidoctor-pdf -a compress $(TOP).adoc
