// test codes for sorting 64M float keys
// only kernel codes. uses 1 float array to sort in-place.
// uses dynamic parallelism feature of cuda
// array size needs to be integer power of 2
// arary size needs to be at least 8192
// benchmark data:

/*
Array elements  GT1030		    std::sort 	        GTX1080ti 
               (benchmark)   (1 core )             (guesstimate)
               (no overclock)
1024            not applicable                            -
2048		    not applicable				      -
4096		    not applicable				      -
8192		    363	    µs		  114 µs		      -
16k			    463	    ms		  248 µs		      -
32k			    746 	µs		  536	µs		      -
64k			    1.23	ms		  1.15ms		      -
128k		    2.32	ms		  2.46ms		      -
256k		    4.87	ms		  5.4	ms		~1.5+ 0.3	ms
512k		    8.72	ms		  11.7ms		~3	+ 0.5	ms
1M			    18.3	ms		  22	ms		~6  + 1.2	ms
2M			    39      ms		  48	ms		~12 + 2.7	ms
4M			    86      ms		  101 ms		~23 + 6.3	ms
8M			    187	    ms		  211 ms		~47 + 14	ms
16M			    407	    ms		  451 ms		~95 + 32	ms
32M			    883	    ms		  940	ms		~190+ 70	ms
64M			    1.93	s		  2.0 s		    ~380+ 150	ms
(float keys)    (copy+kernel )			(copy + kernel)
                                        (using same pcie)
pcie v2.0 4x: 1.4GB/s
fx8150 @ 3.6GHz
4GB RAM 1333MHz
(single channel DDR3)
*/

static constexpr int pow(int base, int exp)
{     
     int res = base;
     int exp_ = exp;
     
     while (exp_ > 1)
     {          
          exp_--;
          res = res * base;
     }

     return res;    
}


constexpr int n = pow(2, 25); // 64M elements
constexpr int l2n= 25;  // log2(n)


// shared memory per block, also number of work per block (2048=minimum, 4096=moderate, 8192=maximum).
constexpr int sharedSize= 8192; 
constexpr int l22k= 13; // log2(sharedSize)
__device__ void compareSwap(float & var1, float &var2, bool dir)
{
     if(var1>var2 && dir)
     {                
               float tmp = var1;
               var1=var2;
               var2=tmp;
     }
     else if(var1<var2 && !dir)
     {
               float tmp = var1;
               var1=var2;
               var2=tmp;   
     }
}
__global__ void computeBox(float * __restrict__ data, const int boxSize, const int leapSize)
{
     const int index = (threadIdx.x + blockIdx.x*blockDim.x);
     const bool dir = ((index%boxSize)<(boxSize/2));
     const int indexOffset = (index / leapSize)*leapSize;
     
     compareSwap(data[index+indexOffset],data[index+indexOffset+leapSize],dir);
}
__global__ void computeBoxForward(float * __restrict__ data, const int boxSize, const int leapSize)
{
     const int index = (threadIdx.x + blockIdx.x*blockDim.x);
     const bool dir = true;
     const int indexOffset = (index / leapSize)*leapSize;
     
     compareSwap(data[index+indexOffset],data[index+indexOffset+leapSize],dir);
}
__device__ void computeBoxShared(float * __restrict__ data, const int boxSize, const int leapSize, const int work)
{
     const int index = threadIdx.x+work*1024;
     const bool dir = ((index%boxSize)<(boxSize/2));
     const int indexOffset = (index / leapSize)*leapSize;
     
     compareSwap(data[index+indexOffset],data[index+indexOffset+leapSize],dir);
}
__device__ void computeBoxForwardShared(float * __restrict__ data, const int boxSize, const int leapSize, const int work)
{
     const int index = threadIdx.x + work*1024;
     const bool dir = true;
     const int indexOffset = (index / leapSize)*leapSize;
     
     compareSwap(data[index+indexOffset],data[index+indexOffset+leapSize],dir);
}
__global__ void bitonicSharedSort(float * __restrict__ data)
{
     const int offset = blockIdx.x * sharedSize;
     __shared__ float sm[sharedSize];
     const int nCopy = sharedSize / 1024;
     const int nWork = sharedSize / 2048;
     for(int i=0;i<nCopy;i++)
     {
          sm[threadIdx.x+i*1024]      = data[threadIdx.x+offset+i*1024];
     }
     __syncthreads();
     int boxSize = 2;
     for(int i=0;i<l22k-1;i++)
     {                       
          for(int leapSize = boxSize/2;leapSize>0;leapSize /= 2)
          {                             
               for(int work=0;work<nWork;work++)
               {                  
                    computeBoxShared(sm,boxSize,leapSize,work);
               }                          
               __syncthreads();
          }
          boxSize*=2;
     }
     
     for(int leapSize = boxSize/2;leapSize>0;leapSize /= 2)
     {           
          for(int work=0;work<nWork;work++)
          {         
               computeBoxForwardShared(sm,boxSize,leapSize,work);
          }                 
          __syncthreads();     
     }
          
     for(int i=0;i<nCopy;i++)
     {
          data[threadIdx.x+offset+i*1024] = sm[threadIdx.x+i*1024];               		      
     }
}
__global__ void bitonicSharedMergeLeaps(float * __restrict__ data, const int boxSizeP, const int leapSizeP)
{
     const int offset = blockIdx.x * sharedSize;
     __shared__ float sm[sharedSize];
     const int nCopy = sharedSize / 1024;
     const int nWork = sharedSize / 2048;
     for(int i=0;i<nCopy;i++)
     {
          sm[threadIdx.x+i*1024] = data[threadIdx.x+offset+i*1024];		 
     }
     __syncthreads();
     
     for(int leapSize = leapSizeP;leapSize>0;leapSize /= 2)
     {                                               
               for(int work=0;work<nWork;work++)
               {
               const int index = threadIdx.x+work*1024;
               const int index2 = threadIdx.x+work*1024+blockIdx.x*blockDim.x*nWork;
               const bool dir = ((index2%boxSizeP)<(boxSizeP/2));
               const int indexOffset = (index / leapSize)*leapSize;
               
               compareSwap(sm[index+indexOffset],sm[index+indexOffset+leapSize],dir);
               }                          
          __syncthreads();
     }

     for(int i=0;i<nCopy;i++)
     {
     data[threadIdx.x+offset+i*1024] = sm[threadIdx.x+i*1024];               		 	    
     }
}

// launch this with 1 cuda thread
// dynamic parallelism = needs something newer than cc v3.0
//extern "C"
//__global__ 
void bitonicSort(float * __restrict__ data)
{     

     bitonicSharedSort<<<(n/sharedSize),1024>>>(data);
     cudaDeviceSynchronize();       

     int boxSize = sharedSize;
     for(int i=l22k-1;i<l2n-1;i++)
     {
              if(boxSize>sharedSize)
              {
                   int leapSize= boxSize/2;
                   for(;leapSize>sharedSize/2;leapSize /= 2)
                   {                                               
                        computeBox<<<(n/1024)/2,1024>>>(data,boxSize,leapSize);    
                        //cudaDeviceSynchronize();                                              											  
                   }
                   cudaDeviceSynchronize();
                   bitonicSharedMergeLeaps<<<(n/sharedSize),1024>>>(data,boxSize, leapSize);
                   cudaDeviceSynchronize();
              }
              else
              {
                   bitonicSharedMergeLeaps<<<(n/sharedSize),1024>>>(data,boxSize, sharedSize/2);
                   cudaDeviceSynchronize();
              }
         boxSize*=2;
         cudaDeviceSynchronize();
     }
     
     
     for(int leapSize = boxSize/2;leapSize>0;leapSize /= 2)
     {                    
         computeBoxForward<<<(n/1024)/2,1024>>>(data,boxSize,leapSize); 
     }
     
     cudaDeviceSynchronize();          		  
}	

void bitonicSortNoShared(float * __restrict__ data)
{            
     int boxSize = 2;
     for(int i=0;i<l2n-1;i++)
     {
          for(int leapSize = boxSize/2;leapSize>0;leapSize /= 2)
          {               
               computeBox<<<(n/1024)/2,1024>>>(data,boxSize,leapSize);
          }
          cudaDeviceSynchronize();
          boxSize*=2;
     }    

     for(int leapSize = boxSize/2;leapSize>0;leapSize /= 2)
     {        
          computeBoxForward<<<(n/1024)/2,1024>>>(data,boxSize,leapSize);
     }
     cudaDeviceSynchronize();
}	

#include <vector>
#include <random>
#include <iostream>
#include <cuda_runtime.h>
#include <algorithm>
#include <chrono>
#include <stdio.h>
#include <execution>

void TestHostQuickSort(std::vector<float>& a, std::vector<float>& b)
{

     //std::sort(a.begin(), a.end());

     std::sort(std::execution::par_unseq, a.begin(), a.end());     

     //  for (int i = 0; i < 5; i++)
     // {
     //     std::cout << a[n - 1 - i] << std::endl;
     // }

}

void TestDeviceBitonicSort(std::vector<float>& a)
{
     cudaError_t err = cudaGetLastError();

     float * d_a = nullptr;

     cudaMalloc((void**)&d_a, sizeof(float) * n);
     cudaMemcpy(d_a, a.data(), sizeof(float) * n, cudaMemcpyDefault);
     //bitonicSort<<<1, 1>>>(d_a);
     //bitonicSort(d_a);
     bitonicSortNoShared(d_a);
     cudaDeviceSynchronize();

     cudaMemcpy(a.data(), d_a, sizeof(float) * n, cudaMemcpyDefault);     

     err = cudaGetLastError();
     std::cout << cudaGetErrorString(err) << std::endl;

     //for (int i = 0; i < 5; i++)
     //{
//
     //    std::cout << a[n - 1 - i] << std::endl;
//
     //}
}

void ValidateResult(std::vector<float>& a)
{

     for (int i = 0; i < n - 1; i++){

          if (a[i] > a[i + 1]) { 

               std::cout << "same or less on " << i << ", " << a[i] << " " << a[i + 1] << std::endl;

          }

     }

}

int main()
{



     std::mt19937 mtRand(2023);
     std::uniform_int_distribution<int> dist1(-n, n);
     std::chrono::system_clock::time_point start;
     std::chrono::microseconds us;

     std::cout << "array size: " << n << std::endl;
    
     std::cout << std::fixed; 

     std::vector<float> a;
     //std::vector<float> b;
     //std::vector<float> c;

     a.resize(n);
     //b.resize(n);
     //c.resize(n);

     for (int i = 0; i < n; i++)
     {
          a[i] = dist1(mtRand);
          //b[i] = a[i];
     }

     //FILE* filePtr;
//
     //filePtr = fopen("unsorted.txt", "w+");
     //for (int i = 0; i < n; i+=50)
     //{
     //     fprintf(filePtr, "%d %.2f \n", i, a[i]);
     //}
     //fclose(filePtr);

     // start = std::chrono::system_clock::now();
     // TestHostQuickSort(a, b);
     // us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now() - start);
     // std::cout << "host took " << us.count() << "us" << std::endl;

     // for (int i = 0; i < n; i++)
     // {
     //     c[i] = a[i];
     // }     

     // for (int i = 0; i < n; i++)
     // {
     //     a[i] = b[i];
     // }     


     start = std::chrono::system_clock::now();
     TestDeviceBitonicSort(a);
     
     us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now() - start);
     std::cout << "device took " << us.count() << "us" << std::endl;


     //FILE* filePtr;

     //filePtr = fopen("res.txt", "w+");
     //for (int i = 0; i < n; i+=50)
     //{
     //     fprintf(filePtr, "%d %.2f \n", i, a[i]);
     //}
     //fclose(filePtr);


     //validate

     // int sum = 0;

     // for (int i = 0; i < n; i++)
     // {          
     //      sum += abs(c[i] - a[i]);
     // }
     // printf("%d \n", sum);





}


