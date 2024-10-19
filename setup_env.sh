#!/bin/bash

# Set up the AWS FPGA environment
echo "Setting up the AWS FPGA environment..."
cd aws-fpga
source vitis_setup.sh

# Set up the Xilinx XRT environment
echo "TODO: Setting up the Xilinx XRT environment..."
echo "      This is painful and should be automated in the future."

# run get_mnist.sh to get the MNIST data
echo "Running get_mnist.sh to get the MNIST data..."
./spooNN/mnist-cnn/deploy/get_mnist.sh

# add NOTE to inform user about AWS configuration
echo "Configure AWS credentials using 'aws configure' to use AWS FPGAs"

echo "NOTE: setup_env.sh has to be done every time you start a new terminal session."
