#############################
# Make file for NUCLEO-8S207K8 board
#############################
BOARD=stm8s207k8
PROGRAMMER=stlinkv21
FLASH_SIZE=65536
BOARD_INC=../inc/stm8s207.inc ../inc/nucleo_8s207.inc
NAME=stm8_wozmon
SDAS=sdasstm8
SDCC=sdcc
OBJCPY=objcpy 
CFLAGS=-mstm8 -lstm8 -L$(LIB_PATH) -I../inc
INC=../inc/
INCLUDES=$(BOARD_INC) $(INC)ascii.inc $(INC)gen_macros.inc 
BUILD=build/
SRC=stm8_wm.asm
OBJECT=$(BUILD)$(BOARD)/$(NAME).rel
OBJECTS=$(BUILD)$(BOARD)/$(SRC:.asm=.rel)
LIST=$(BUILD)$(BOARD)/$(NAME).lst
FLASH=stm8flash

.PHONY: all

all: clean asm #flash 

asm:
	#
	# "*************************************"
	# "compiling $(NAME)  for $(BOARD)      "
	# "*************************************"
	$(SDAS) -g -l -o $(BUILD)$(BOARD)/$(NAME).rel $(SRC) 
	$(SDCC) $(CFLAGS) -Wl-u -o $(BUILD)$(BOARD)/$(NAME).ihx $(OBJECT) 
	objcopy -Iihex -Obinary  $(BUILD)$(BOARD)/$(NAME).ihx $(BUILD)$(BOARD)/$(NAME).bin 
	# 
	@ls -l  $(BUILD)$(BOARD)/$(NAME).bin 
	# 


.PHONY: clean 
clean:
	#
	# "***************"
	# "cleaning files"
	# "***************"
	rm -f $(BUILD)$(BOARD)/*
flash: $(LIB)
	#
	# "******************"
	# "flashing $(BOARD) "
	# "******************"
	$(FLASH) -c $(PROGRAMMER) -p $(BOARD) -s flash -w $(BUILD)$(BOARD)/$(NAME).ihx 

