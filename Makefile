############################## Setting up Project Variables ##############################
KERNEL ?= cnndetect
N_KERNELS ?= 1
HOST_APP ?= cnndetect_test

AWS_BUCKET_NAME ?= fpga-tars
AWS_DCP_FOLDER ?= builds
AWS_LOGS_FOLDER ?= logs

DATASET_PATH ?= $(shell pwd)/mnist.t
ifeq ($(wildcard $(DATASET_PATH)),)
$(error DATASET_PATH does not exist, please ensure mnist.t is present in the project directory)
endif

HOST_ARCH ?= x86
DEVICE ?= $(AWS_PLATFORM)
ifndef DEVICE
$(error DEVICE is not set. Please set DEVICE variable or ensure AWS_PLATFORM is defined)
endif
DEVICE := $(DEVICE)


# check if faketime tool is installed
FAKETIME_CHECK := $(shell which faketime 2>/dev/null)
ifeq ($(FAKETIME_CHECK),)
$(error faketime could not be found, install it with 'sudo apt-get install faketime')
endif

PWD = $(shell readlink -f .)
SPOONN_DIR = $(PWD)/spooNN
ifeq ($(wildcard $(SPOONN_DIR)),)
$(error SPOONN_DIR does not exist, clone the spooNN repository from https://github.com/guna-s/spooNN.git)
endif

# Points to vitis examples top directory

ifeq ($(wildcard $(VITIS_DIR)),)
$(error VITIS_DIR is not set or does not exist, run aws-fpga/vitis_setup.sh)
else
ABS_COMMON_REPO = $(VITIS_DIR)/examples/xilinx
endif

TARGET := sw_emu
HOST_ARCH := x86
SYSROOT := 

include ./utils.mk

XSA := $(call device2xsa, $(DEVICE))
TEMP_DIR := ./_x.$(TARGET).$(XSA)
BUILD_DIR := ./build_dir.$(TARGET).$(XSA)

# SoC variables
RUN_APP_SCRIPT = ./run_app.sh
PACKAGE_OUT = ./package.$(TARGET)

LAUNCH_EMULATOR = $(PACKAGE_OUT)/launch_$(TARGET).sh
RESULT_STRING = TEST PASSED

VPP := v++
SDCARD := sd_card

include $(ABS_COMMON_REPO)/common/includes/opencl/opencl.mk
CXXFLAGS += $(opencl_CXXFLAGS) -Wall -O0 -g -std=c++11
LDFLAGS += $(opencl_LDFLAGS)

############################## Setting up Host Variables ##############################
#Include Required Host Source Files
CXXFLAGS += -I$(PWD)/spooNN/mnist-cnn/training
CXXFLAGS += -I$(PWD)/spooNN/mnist-cnn/hls
CXXFLAGS += -I$(ABS_COMMON_REPO)/common/includes/xcl2
HOST_SRCS += $(ABS_COMMON_REPO)/common/includes/xcl2/xcl2.cpp ./src/host.cpp 
CXXFLAGS += -Wno-int-in-bool-context
# Host compiler global settings
CXXFLAGS += -fmessage-length=0
LDFLAGS += -lOpenCL -lrt -lstdc++ 

ifneq ($(HOST_ARCH), x86)
	LDFLAGS += --sysroot=$(SYSROOT)
endif

############################## Setting up Kernel Variables ##############################
# Kernel compiler global settings
CLFLAGS += -t $(TARGET) --platform $(DEVICE) --save-temps 
CLFLAGS += -I/usr/include/x86_64-linux-gnu
CLFLAGS += -I$(PWD)/spooNN/hls-nn-lib
CLFLAGS += -I$(PWD)/spooNN/mnist-cnn/training
ifneq ($(TARGET), hw)
	CLFLAGS += -g
endif
CLFLAGS += --nk $(KERNEL):$(N_KERNELS)

EXECUTABLE = ./$(HOST_APP)
CMD_ARGS = $(BUILD_DIR)/$(KERNEL).xclbin
EMCONFIG_DIR = $(TEMP_DIR)
EMU_DIR = $(SDCARD)/data/emulation

############################## Declaring Binary Containers ##############################
BINARY_CONTAINERS += $(BUILD_DIR)/$(KERNEL).xclbin
BINARY_CONTAINER_$(KERNEL)_OBJS += $(TEMP_DIR)/$(KERNEL).xo

############################## Setting Targets ##############################
CP = cp -rf

.PHONY: all clean cleanall docs emconfig
all: check-devices $(EXECUTABLE) $(BINARY_CONTAINERS) emconfig sd_card

.PHONY: host
host: $(EXECUTABLE)

.PHONY: build
build: check-vitis $(BINARY_CONTAINERS)

.PHONY: xclbin
xclbin: build

############################## Setting Rules for Binary Containers (Building Kernels) ##############################
$(TEMP_DIR)/$(KERNEL).xo: src/$(KERNEL).cpp
	mkdir -p $(TEMP_DIR)
	faketime -f "-4y" $(VPP) -c -k $(KERNEL) $(CLFLAGS) --temp_dir $(TEMP_DIR)  -I'$(<D)' -o'$@' '$<'
$(BUILD_DIR)/$(KERNEL).xclbin: $(BINARY_CONTAINER_$(KERNEL)_OBJS)
	mkdir -p $(BUILD_DIR)
ifeq ($(HOST_ARCH), x86)
	faketime -f "-4y" $(VPP) -l $(LDCLFLAGS) $(CLFLAGS) --temp_dir $(BUILD_DIR)  -o'$(BUILD_DIR)/$(KERNEL).link.xclbin' $(+)
	faketime -f "-4y" $(VPP) -p $(BUILD_DIR)/$(KERNEL).link.xclbin -t $(TARGET) --platform $(DEVICE) --package.out_dir $(PACKAGE_OUT) -o $(BUILD_DIR)/$(KERNEL).xclbin
else
	faketime -f "-4y" $(VPP) -l $(LDCLFLAGS) $(CLFLAGS) --temp_dir $(BUILD_DIR) -o'$(BUILD_DIR)/$(KERNEL).xclbin' $(+)
endif

############################## Setting Rules for Host (Building Host Executable) ##############################
$(EXECUTABLE): $(HOST_SRCS) | check-xrt
		$(CXX) -o $@ $^ $(CXXFLAGS) $(LDFLAGS)

emconfig:$(EMCONFIG_DIR)/emconfig.json
$(EMCONFIG_DIR)/emconfig.json:
	emconfigutil --platform $(DEVICE) --od $(EMCONFIG_DIR)

############################## Setting Essential Checks and Running Rules ##############################
run: all
ifeq ($(TARGET),$(filter $(TARGET),sw_emu hw_emu))
ifeq ($(HOST_ARCH), x86)
	$(CP) $(EMCONFIG_DIR)/emconfig.json .
	XCL_EMULATION_MODE=$(TARGET) $(EXECUTABLE) $(BUILD_DIR)/$(KERNEL).xclbin $(DATASET_PATH)
else
	$(ABS_COMMON_REPO)/common/utility/run_emulation.pl "${LAUNCH_EMULATOR} | tee run_app.log" "${RUN_APP_SCRIPT} $(TARGET)" "${RESULT_STRING}" "7"
endif
else
ifeq ($(HOST_ARCH), x86)
	$(EXECUTABLE) $(BUILD_DIR)/$(KERNEL).xclbin $(DATASET_PATH)
endif
endif


.PHONY: test
test: $(EXECUTABLE)
ifeq ($(TARGET),$(filter $(TARGET),sw_emu hw_emu))
ifeq ($(HOST_ARCH), x86)
	XCL_EMULATION_MODE=$(TARGET) $(EXECUTABLE) $(BUILD_DIR)/$(KERNEL).xclbin $(DATASET_PATH)
else
	$(ABS_COMMON_REPO)/common/utility/run_emulation.pl "${LAUNCH_EMULATOR} | tee embedded_run.log" "${RUN_APP_SCRIPT} $(TARGET)" "${RESULT_STRING}" "7"
endif
else
ifeq ($(HOST_ARCH), x86)
	$(EXECUTABLE) $(BUILD_DIR)/$(KERNEL).xclbin $(DATASET_PATH)
else
	$(ECHO) "Please copy the content of sd_card folder and data to an SD Card and run on the board"
endif
endif

############################## Cleaning Rules ##############################
# Cleaning stuff
clean:
	-$(RMDIR) $(EXECUTABLE) $(XCLBIN)/{*sw_emu*,*hw_emu*} 
	-$(RMDIR) profile_* TempConfig system_estimate.xtxt *.rpt *.csv .run
	-$(RMDIR) src/*.ll *v++* .Xil emconfig.json dltmp* xmltmp* *.log *.jou *.wcfg *.wdb

cleanall: clean
	-$(RMDIR) build_dir* sd_card*
	-$(RMDIR) package.*
	-$(RMDIR) _x* *xclbin.run_summary qemu-memory-_* emulation _vimage pl* start_simulation.sh *.xclbin

aws:
	$(VITIS_DIR)/tools/create_vitis_afi.sh -xclbin=$(BUILD_DIR)/$(KERNEL).xclbin \
		-o=$(KERNEL) \
		-s3_bucket=$(AWS_BUCKET_NAME) -s3_dcp_key=$(AWS_DCP_FOLDER) -s3_logs_key=$(AWS_LOGS_FOLDER)

############################## Help Section ##############################
.PHONY: help
# Default target when no arguments are provided
.DEFAULT_GOAL := help

# Make sure 'help' is the default target
ifeq ($(MAKECMDGOALS),)
    MAKECMDGOALS := help
endif


help::
	$(ECHO) "Makefile Usage:"
	$(ECHO) "  make all TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to generate the design for specified Target and Shell."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and EDGE_COMMON_SW is required for SoC shells"
	$(ECHO) ""
	$(ECHO) "  make clean "
	$(ECHO) "      Command to remove the generated non-hardware files."
	$(ECHO) ""
	$(ECHO) "  make cleanall"
	$(ECHO) "      Command to remove all the generated files."
	$(ECHO) ""
	$(ECHO) "  make build TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to build xclbin application."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and EDGE_COMMON_SW is required for SoC shells"
	$(ECHO) ""
	$(ECHO) "  make host HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to build host application."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and EDGE_COMMON_SW is required for SoC shells"
	$(ECHO) ""
	$(ECHO)  "  make test DEVICE=<FPGA platform>"
	$(ECHO)  "     Command to run the application. This is same as 'run' target but does not have any makefile dependency."
	$(ECHO)  ""
	$(ECHO) "  make run TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to run application in emulation."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and EDGE_COMMON_SW is required for SoC shells"
	$(ECHO) ""
	$(ECHO) "  make aws TARGET=hw DEVICE=$AWS_PLATFORM HOST_ARCH=x86"
	$(ECHO) "      Command to publish kernel to AWS environment."
	$(ECHO) "      *$(KERNEL).xclbin* has to be built before running this command using: make build."
	$(ECHO) "      *$(KERNEL).xclbin* gets copied to AWS S3 bucket: $(AWS_BUCKET_NAME) in folder: $(AWS_DCP_FOLDER)."
	$(ECHO) "      Logs are saved in AWS S3 bucket: $(AWS_BUCKET_NAME) in folder: $(AWS_LOGS_FOLDER)."
	$(ECHO) "      AFI of this build is stored in the current directory."
	$(ECHO) "      *$(KERNEL).awsxclbin* is the output of this command and is used to run the kernel on AWS F1 FPGAs."
	$(ECHO) ""
	
	$(ECHO) ""
	