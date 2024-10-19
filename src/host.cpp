// #define DEBUG

#define AP_INT_MAX_W 16384

#include <ap_int.h>
#include "mnist-cnn-config-1W5A.h"
// #include "mnist-cnn-params-1W5A.h"
#include "loader.h"
#include "xcl2.hpp" // This file is required for OpenCL C++ wrapper APIs


using namespace std;

cl::Context connectToDevice(const std::string &binaryFile, cl::Kernel &krnl_vector_add, cl::CommandQueue &q)
{
	cl_int err;
	cl::Context context;
	auto devices = xcl::get_xil_devices();
	auto fileBuf = xcl::read_binary_file(binaryFile);
	cl::Program::Binaries bins{{fileBuf.data(), fileBuf.size()}};
	bool valid_device = false;

	for (unsigned int i = 0; i < devices.size(); i++)
	{
		auto device = devices[i];
		OCL_CHECK(err, context = cl::Context(device, NULL, NULL, NULL, &err));
		OCL_CHECK(err, q = cl::CommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &err));
		std::cout << "Trying to program device[" << i << "]: " << device.getInfo<CL_DEVICE_NAME>() << std::endl;
		cl::Program program(context, {device}, bins, NULL, &err);
		if (err != CL_SUCCESS)
		{
			std::cout << "Failed to program device[" << i << "] with xclbin file!\n";
		}
		else
		{
			std::cout << "Device[" << i << "]: program successful!\n";
			OCL_CHECK(err, krnl_vector_add = cl::Kernel(program, "cnndetect", &err));
			valid_device = true;
			break;
		}
	}
	if (!valid_device)
	{
		throw std::runtime_error("Failed to program any device found, exit!\n");
	}
	
	return context;
}

void submitInputData(cl::Context& context, cl::CommandQueue& q, cl::Kernel& kernel,
                     cl::Buffer& buffer_input, cl::Buffer& buffer_output, unsigned int numReps) {
    cl_int err;
    
    OCL_CHECK(err, err = kernel.setArg(0, buffer_input));
    OCL_CHECK(err, err = kernel.setArg(1, buffer_output));
    OCL_CHECK(err, err = kernel.setArg(2, numReps));

    OCL_CHECK(err, err = q.enqueueMigrateMemObjects({buffer_input}, 0 /* 0 means from host*/));
    OCL_CHECK(err, err = q.enqueueTask(kernel));
}

void receiveOutput(cl::CommandQueue& q, cl::Buffer& buffer_output) {
    cl_int err;
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects({buffer_output}, CL_MIGRATE_MEM_OBJECT_HOST));
	q.finish();
}

int main(int argc, char **argv)
{
	// Check for correct number of arguments
	if (argc < 2)
	{
		std::cout << "No XCLBIN file provided" << std::endl;
		std::cout << "Usage: " << argv[0] << " <XCLBIN File> <pathToDataset>" << std::endl;
		return EXIT_FAILURE;
	}
	std::string binaryFile = argv[1];

	// Load dataset
#define NUM_SAMPLES 1
	if (argc < 3)
	{
		std::cout << "No path to dataset provided" << std::endl;
		std::cout << "Usage: " << argv[0] << " <XCLBIN File> <pathToDataset>" << std::endl;
		return EXIT_FAILURE;
	}
	char *pathToDataset = argv[2];
	loader load = loader();
	load.load_libsvm_data(pathToDataset, NUM_SAMPLES, 784, 10);
	load.x_normalize(0, 'r');

	// Connect to device
	cl::Kernel krnl_vector_add;
	cl::CommandQueue q;
	cl::Context context = connectToDevice(binaryFile, krnl_vector_add, q);

	// prepare input data
	size_t buffer_size = sizeof(ap_uint<512>) * 14 * NUM_SAMPLES;	// Per image, we need 14 lines
	const unsigned int data_points_per_line = 448 / L0_Ibit;	// One line will contain 448 useful bits
	std::vector<ap_uint<512>, aligned_allocator<ap_uint<512>>> source_in(buffer_size);
	std::vector<ap_uint<512>, aligned_allocator<ap_uint<512>>> results_out(buffer_size);

	// fill source_in with data from load.x
	unsigned int index = 0;
	// uint8_t aa = 0xA0;
	for (unsigned int i = 0; i < (14* NUM_SAMPLES); i++) {
		ap_uint<512> temp = 0;
		for (unsigned int j = 0; j < data_points_per_line-1; j++) {
			temp(L0_Ibit*(j+1)-1, L0_Ibit*j) =((unsigned int)(load.x[index++]*255.0)); // aa++;
		}
		for (unsigned int j = 55; j < 56; j++) {
			temp( L0_Ibit*(j+1)-1, L0_Ibit*j ) = ((unsigned int)(load.x[index++]*255.0)); //0xBB;
		}
		for (unsigned int j = 56; j < 64; j++) {
			temp( L0_Ibit*(j+1)-1, L0_Ibit*j ) = 0x00; //0xFF;
		}
		source_in[i] = temp;
		cout << "host:inputStream[" << i << "]: " << hex << setfill('0') << setw(128) << temp << dec << endl;
	}
	// Create buffers
	cl_int err;
	cl::Buffer buffer_input, buffer_output;
	OCL_CHECK(err, buffer_input = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
											buffer_size, const_cast<ap_uint<512>*>(source_in.data()), &err));
	OCL_CHECK(err, buffer_output = cl::Buffer(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
											buffer_size, const_cast<ap_uint<512>*>(results_out.data()), &err));

	// Submit data to device
	submitInputData(context, q, krnl_vector_add, buffer_input, buffer_output, NUM_SAMPLES);
	
	// Receive output from device and copy to outputBuffer
	receiveOutput(q, buffer_output);

	// process output
	unsigned long MASK = ((long)1 << L5_Mbit) - 1;
	unsigned int count_trues = 0;
	for (unsigned int i = 0; i < NUM_SAMPLES; i++) {
		cout << "outputBuffer[" << i << "]: " << hex << results_out[i] << dec << endl;
		int max = 0;
		unsigned int prediction = -1;
		for (unsigned int j = 0; j < L5_Dout; j++) {
			int temp = (results_out[i] >> (j*L5_Mbit)) & MASK;
			temp = temp >> SCALE_BITS;
			cout << "outputBuffer[" << i << "][" << j << "]: " << static_cast<int>(temp) << endl;
			if (temp > max){
				max = temp;
				prediction = j;
			}
		}
		cout << "prediction: " << prediction << endl;
		if (load.y[i*10 + prediction] == 1) { 
			count_trues++;
		}
	}
	cout << count_trues << " correct out of " << NUM_SAMPLES << endl;

	bool match = count_trues == NUM_SAMPLES;
	std::cout << "TEST " << (match ? "PASSED" : "FAILED") << std::endl;
	return (match ? EXIT_SUCCESS : EXIT_FAILURE);
}