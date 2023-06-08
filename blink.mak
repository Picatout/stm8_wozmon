BOARD=stm8s207k8
PROGRAMMER=stlinkv21
FLASH_SIZE=65536
BOARD_INC=../inc/stm8s207.inc ../inc/nucleo_8s207.inc
NAME=blink
SDAS=sdasstm8
SDCC=sdcc
OBJCPY=objcpy 
CFLAGS=-mstm8 -lstm8 -L$(LIB_PATH) -I../inc
INC=../inc/
INCLUDES=$(BOARD_INC) $(INC)gen_macros.inc 
BUILD=build/
SRC=blink.asm
OBJECT=$(BUILD)$(NAME).rel
OBJECTS=$(BUILD)$(SRC:.asm=.rel)
LIST=$(BUILD)$(NAME).lst


blink: blink.asm 
	#
	# "*********************"
	# "compiling $(NAME)    "
	# "*********************"
	$(SDAS) -g -l -o $(BUILD)$(NAME).rel $(SRC) 
	$(SDCC) $(CFLAGS) -Wl-u -o $(BUILD)$(NAME).ihx $(OBJECT) 
	objcopy -Iihex -Obinary  $(BUILD)$(NAME).ihx $(BUILD)$(NAME).bin 
	# 
	@ls -l  $(BUILD)$(NAME).bin 
	# 
