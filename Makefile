all: slides.html

slides.html: slides.md template.html
	pandoc -t dzslides \
		   --template template.html \
		   --self-contained \
	       -s slides.md \
		   -o slides.html

clean:
	-rm slides.html
