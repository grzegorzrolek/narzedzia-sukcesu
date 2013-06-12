# Makefile for Narzędzia Sukcesu the logotype font
# Copyright 2013 Grzegorz Rolek


TARGET = build/NarzedziaSukcesu.ttf
NULL = Null.ttf

# Helper files to make some methodology in fusing the individual tables possible.
BASICS = $(addprefix .,head name maxp glyf cmap hmtx hhea post)
HINTS = .hints
MORPHING = .morx
KERNING = .kern
OTLAYOUT = .otlayout

# First the basics (note the table order), hints, and the smarts (without particular order).
all: $(BASICS) $(HINTS) $(MORPHING) $(KERNING) $(OTLAYOUT)

$(OTLAYOUT): features.fea $(NULL) | $(TARGET)
	makeotf -f $(TARGET) -o $(basename $(TARGET)).otf -ff features.fea
	mv $(basename $(TARGET)).otf $(TARGET)
	ftxdumperfuser -k -t 'OS/2' $(TARGET)
	for TABLE in head name cmap hhea post; do ftxdumperfuser -d $$TABLE.xml -t $$TABLE $(TARGET); done
	@touch $@

$(KERNING): kern.xml $(NULL) | $(TARGET)
	ftxdumperfuser -d $< -g -t kern $(TARGET)
	@touch $@

$(MORPHING): morphing.mif $(NULL) | $(TARGET)
	ftxenhancer -m $< $(TARGET)
	@touch $@

$(HINTS): .glyf $(NULL) | $(TARGET)
	ttfautohint -f -n -c $(TARGET) $(basename $(TARGET))_hinted.ttf
	mv $(basename $(TARGET))_hinted.ttf $(TARGET)
	@touch $@

$(BASICS): .%: %.xml $(NULL) | $(TARGET) 
	ftxdumperfuser -d $< -t $(basename $<) $(TARGET)
	@touch $@

$(TARGET): $(NULL) | build
	cp $< $@

build:
	mkdir $@

test:
	@ftxvalidator -T -o test.out $(TARGET)

list:
	@ftxdumperfuser -l $(TARGET)

cleanall: clean
	@rm -rf build

clean:
	@rm -rf $(BASICS) $(HINTS) $(MORPHING) $(KERNING) $(OTLAYOUT) build/current.fpr test.out
