# FPGA-Accelerated MNIST Image Classification using spooNN and HLS-NN-Lib

This project implements an FPGA-accelerated neural network for MNIST image classification using the spooNN architecture and HLS-NN-Lib, targeting the AWS FPGA platform with Vitis HLS.

## Project Overview

- **Neural Network Architecture**: Adopts the spooNN (Sparse Parallel Object-Oriented Neural Network) architecture
- **Dataset**: MNIST handwritten digit classification
- **Hardware Target**: AWS FPGA (F1 instances)
- **Development Platform**: Vitis HLS (High-Level Synthesis)
- **Key Components**:
  - Pre-trained spooNN model
  - HLS-NN-Lib for efficient FPGA implementation

## Features

- High-performance image classification on FPGA
- Utilizes sparse neural network techniques for improved efficiency
- Seamless integration with AWS FPGA instances
- Demonstrates the power of high-level synthesis for FPGA development

## Getting Started

1. Clone this repository
2. Set up the AWS FPGA development environment (see `setup_env.sh`)
3. Synthesize the HLS design using Vitis HLS
4. Build and run the FPGA bitstream on an AWS F1 instance

## Dependencies

- AWS FPGA Vitis Development Kit
- Vitis 2020.2
- HLS-NN-Lib
- Pre-trained spooNN model weights
- Xilinx XRT (Xilinx Runtime Library) for simulation


## Environment Setup

Before building and running the project, you need to set up the AWS FPGA development environment.
**NOTE: this has to be done every time you start a new terminal session.**

To set up the environment, run the following command:

```
source ./setup_env.sh
```


## Build and Run

To build and run the project on software emulation mode, use the provided Makefile with the following command:

```
make DEVICE=$AWS_PLATFORM HOST_ARCH=x86 TARGET=sw_emu build host run
```

To build and run the project on hardware emulation mode, use the following command:

```
make DEVICE=$AWS_PLATFORM HOST_ARCH=x86 TARGET=hw_emu build host run
```

To build and run the project on hardware mode, use the following command:

```
make DEVICE=$AWS_PLATFORM HOST_ARCH=x86 TARGET=hw build host run
```

## Performance

(Add specific performance metrics once available, such as inference time, resource utilization, etc.)

## Contributing

Contributions to improve the project are welcome. Please submit pull requests or open issues for any enhancements, bug fixes, or suggestions.

## License

(Specify the license under which this project is released)

## Acknowledgements

- spooNN project for the neural network architecture
- HLS-NN-Lib developers for the efficient FPGA neural network library
- AWS for the FPGA platform and development tools
