# by default will build all the executables
TARGET = sandbox
all: $(TARGET)

# using linker to create executable from the object file
% : %.o
	ld 	$< 	-o $@
# assemble any .asm file in the src directory to object file using nasm
# $< is the first dependency, $@ is the target

%.o:%.asm
	nasm -f elf64 $< -o $@
.PHONY: clean

clean:
	rm $(TARGET).o $(TARGET)
