#############################
# Make file for NUCLEO-8S207K8 MCU
#############################
NAME=stm8_picmon
SDAS=sdasstm8
SDCC=sdcc
OBJCPY=objcpy 
CFLAGS=-mstm8 -lstm8 -L$(LIB_PATH) -I../inc
INC=inc
INCLUDES=$(MCU_INC) $(INC)ascii.inc $(INC)gen_macros.inc 
BUILD=build/
SRC=stm8_picmon.asm
OBJECT=$(BUILD)$(MCU)/$(NAME).rel
OBJECTS=$(BUILD)$(MCU)/$(SRC:.asm=.rel)
LIST=$(BUILD)$(MCU)/$(NAME).lst
FLASH=stm8flash

.PHONY: all

all: clean asm

asm:
	#
	# "*************************************"
	# "compiling $(NAME)  for $(MCU)      "
	# "*************************************"
	$(SDAS) -g -l -o $(BUILD)$(MCU)/$(NAME).rel $(SRC) 
	$(SDCC) $(CFLAGS) -Wl-u -o $(BUILD)$(MCU)/$(NAME).ihx $(OBJECT) 
	objcopy -Iihex -Obinary  $(BUILD)$(MCU)/$(NAME).ihx $(BUILD)$(MCU)/$(NAME).bin 
	# 
	@ls -l  $(BUILD)$(MCU)/$(NAME).bin 
	# 


.PHONY: clean 
clean:
	#
	# "***************"
	# "cleaning files"
	# "***************"
	rm -f $(BUILD)$(MCU)/*
flash: $(LIB)
	#
	# "******************"
	# "flashing $(MCU) "
	# "******************"
	$(FLASH) -c $(PROGRAMMER) -p $(MCU) -s flash -w $(BUILD)$(MCU)/$(NAME).ihx 

