#include <cuda.h>
#include "DynamicKernel.h"
#include "AriesColumnDataIterator.hxx"
#include "utils/string_util.h"
#include "server/Configuration.h"
#include "CpuTimer.h"

BEGIN_ARIES_ACC_NAMESPACE

void AriesDynamicKernelManager::SetModuleAccessed( const string& code )
{
    //update lru
    auto it = std::find( m_moduleCodesLru.begin(), m_moduleCodesLru.end(), code );
    assert( it != m_moduleCodesLru.end() );
    string val = *it;
    m_moduleCodesLru.erase( it );
    m_moduleCodesLru.push_front( val );
}

void AriesDynamicKernelManager::AddModule( const string& code, AriesCUModuleInfoSPtr moduleInfo )
{
    unique_lock< mutex > lock( m_mutex );
    if( m_modules.find( code ) == m_modules.end() )
    {
        m_modules.insert( { code, moduleInfo } );
        m_moduleCodesLru.push_front( code );
        RemoveOldModulesIfNecessary();
    }
    else
        SetModuleAccessed( code );
}

void AriesDynamicKernelManager::RemoveOldModulesIfNecessary()
{
    assert( m_modules.size() == m_moduleCodesLru.size() );
    int needRemoveCount = m_moduleCodesLru.size() - LRU_COUNT;
    if( needRemoveCount > 0 )
    {
        while( needRemoveCount-- )
        {
            m_modules.erase( m_moduleCodesLru.back() );
            m_moduleCodesLru.pop_back();
        }
    }
}

AriesCUModuleInfoSPtr AriesDynamicKernelManager::FindModule( const string& code )
{
    unique_lock< mutex > lock( m_mutex );
    AriesCUModuleInfoSPtr result;
    auto it = m_modules.find( code );
    if( it != m_modules.end() )
    {
        result = it->second;
        SetModuleAccessed( code );
    }
    return result;
}

AriesCUModuleInfoSPtr AriesDynamicKernelManager::CompileKernels( const AriesDynamicCodeInfo& code )
{
    AriesCUModuleInfoSPtr moduleInfo = FindModule( code.KernelCode );
    if( moduleInfo )
        return moduleInfo;
    else
        moduleInfo = std::make_shared< AriesCUModuleInfo >();
    vector< CUmoduleSPtr > result;
    // m_ctx->timer_begin();
    nvrtcProgram prog;
    NVRTC_SAFE_CALL( nvrtcCreateProgram(&prog,         // prog
            code.KernelCode.c_str(),// buffer
            0,// name
            0,// numHeaders
            NULL,// headers
            NULL) );// includeNames
    static std::string include_path( "-I " + aries_utils::get_current_work_directory() + "/include" );
    // Compile the program for compute_30 with fmad disabled.
    // we assmue all device has same compute capability.
    aries::Configuartion& config = aries::Configuartion::GetInstance();
    string computeVersionParam = "--gpu-architecture=compute_" + std::to_string( config.GetComputeVersionMajor() ) + std::to_string( config.GetComputeVersionMinor() );
    const char *opts[] =
    { computeVersionParam.c_str(), "--relocatable-device-code=true", "--std=c++14", "--define-macro=__WORDSIZE=64", include_path.c_str() };
    nvrtcResult compileResult = nvrtcCompileProgram( prog,  // prog
            5,     // numOptions
            opts ); // options
    // LOG( INFO ) << "nvrtcCompileProgram gpu time: " << m_ctx->timer_end();

    // Obtain compilation log from the program.
    size_t logSize;
    NVRTC_SAFE_CALL( nvrtcGetProgramLogSize( prog, &logSize ) );
    char *log = new char[logSize];
    NVRTC_SAFE_CALL( nvrtcGetProgramLog( prog, log ) );
    LOG( INFO ) << log;
    delete[] log;
    if( compileResult != NVRTC_SUCCESS )
    {
        LOG( INFO ) << "dyn compile error\n";
        return moduleInfo;
    }
    // Obtain PTX from the program.
    size_t ptxSize;
    NVRTC_SAFE_CALL( nvrtcGetPTXSize( prog, &ptxSize ) );
    LOG( INFO ) << "ptx size is:" << ptxSize << " bytes" << std::endl;
    char *ptx = new char[ptxSize];
    NVRTC_SAFE_CALL( nvrtcGetPTX( prog, ptx ) );
    //std::cout<<ptx<<std::endl;
    // Destroy the program.
    NVRTC_SAFE_CALL( nvrtcDestroyProgram( &prog ) );
    // Load the generated PTX and get a handle to the kernel.

    int32_t oldDeviceId;// = m_ctx->active_device_id();
    cudaGetDevice(&oldDeviceId);

    CUdevice cuDevice;
    CUcontext context;
    CU_SAFE_CALL( cuDeviceGet( &cuDevice, oldDeviceId ) );
    CU_SAFE_CALL( cuDevicePrimaryCtxRetain( &context, cuDevice ) );
    CU_SAFE_CALL( cuCtxPushCurrent( context ) );

    CUlinkState linkState;
    CU_SAFE_CALL( cuLinkCreate( 0, 0, 0, &linkState ) );

    // m_ctx->timer_begin();
    static std::string library_path( aries_utils::get_current_work_directory() + "/lib/libariesdatatype.a" );
    CU_SAFE_CALL( cuLinkAddFile( linkState, CU_JIT_INPUT_LIBRARY, library_path.c_str(), 0, 0, 0 ) );
    // LOG( INFO ) << "cuLinkAddFile gpu time: " << m_ctx->timer_end();

    // m_ctx->timer_begin();
    CU_SAFE_CALL( cuLinkAddData( linkState, CU_JIT_INPUT_PTX, ( void * )ptx, ptxSize, 0, 0, 0, 0 ) );
    // LOG( INFO ) << "cuLinkAddData gpu time: " << m_ctx->timer_end();

    delete[] ptx;
    size_t cubinSize;
    void *cubin;
    CU_SAFE_CALL( cuLinkComplete( linkState, &cubin, &cubinSize ) );

    int deviceCount;
    cudaGetDeviceCount( &deviceCount );
    for( int deviceId = 0; deviceId < deviceCount; ++deviceId )
    {
        CUmoduleSPtr module( new CUmodule, []( CUmodule* p )
        {   CU_SAFE_CALL( cuModuleUnload( *p ) ); delete p;} );
        cudaSetDevice( deviceId );
        CU_SAFE_CALL( cuModuleLoadData( module.get(), cubin ) );
        result.push_back( module );
    }

    cudaSetDevice( oldDeviceId );

    CU_SAFE_CALL( cuLinkDestroy( linkState ) );
    CU_SAFE_CALL( cuCtxPopCurrent( nullptr ) );
    CU_SAFE_CALL( cuDevicePrimaryCtxRelease( cuDevice ) );

    moduleInfo->Modules = std::move( result );
    moduleInfo->FunctionKeyNameMapping = code.FunctionKeyNameMapping;
    AddModule( code.KernelCode, moduleInfo );
    return moduleInfo;
}

void AriesDynamicKernelManager::CallKernel( const vector< CUmoduleSPtr >& modules,
                                            const char* functionName,
                                            const AriesColumnDataIterator *input,
                                            const index_t *leftIndices,
                                            const index_t *rightIndices,
                                            int tupleNum,
                                            const int8_t** constValues,
                                            const vector< AriesDynamicCodeComparator >& items,
                                            int8_t *output ) const
{
    ARIES_ASSERT( !modules.empty(), "CUDA module for " + string( functionName ) + " is empty, no dynamic code or no compiling for it?" );
    // m_ctx->timer_begin();
    CUdevice dev;
    cudaGetDevice( &dev );//m_ctx->active_device_id();
    ARIES_ASSERT( dev < modules.size(),
            "CUDA module for device " + std::to_string( dev ) + " is empty, no dynamic code or no compiling for it?" );
    CUmoduleSPtr module = modules[dev];

    AriesArraySPtr< CallableComparator* > comparators = CreateInComparators( module, items );
    CallableComparator** operators = comparators->GetData();
    CUfunction kernel;
    CU_SAFE_CALL( cuModuleGetFunction( &kernel, *module, functionName ) );

    void *args[] =
    { &input, &leftIndices, &rightIndices, &tupleNum, &constValues, &operators, &output };

    int numThreads = 256;
    int numBlocks = ( tupleNum + numThreads - 1 ) / numThreads;
    CUresult res = cuLaunchKernel( kernel, numBlocks, 1, 1,    // grid dim
            numThreads, 1, 1,   // block dim
            0, NULL,             // shared mem and stream
            args, 0 );           // arguments
    CU_SAFE_CALL( res );
    CU_SAFE_CALL( cuCtxSynchronize() );
    DestroyComparators( comparators );
    // LOG( INFO ) << "CallKernel gpu time: " << m_ctx->timer_end();
}

void AriesDynamicKernelManager::CallKernel( const vector< CUmoduleSPtr >& modules,
                                            const char* functionName,
                                            const AriesColumnDataIterator *input,
                                            size_t leftCount,
                                            size_t rightCount,
                                            size_t tupleNum,
                                            int* left_unmatched_flag,
                                            int* right_unmatched_flag,
                                            const int8_t** constValues,
                                            const vector< AriesDynamicCodeComparator >& items,
                                            int *left_output,
                                            int *right_output,
                                            unsigned long long int* output_count ) const
{
    ARIES_ASSERT( !modules.empty(), "CUDA module for " + string( functionName ) + " is empty, no dynamic code or no compiling for it?" );
    // m_ctx->timer_begin();
    CUdevice dev; // = m_ctx->active_device_id();
    cudaGetDevice( &dev );
    ARIES_ASSERT( dev < modules.size(),
            "CUDA module for device " + std::to_string( dev ) + " is empty, no dynamic code or no compiling for it?" );
    CUmoduleSPtr module = modules[dev];

    AriesArraySPtr< CallableComparator* > comparators = CreateInComparators( module, items );
    CallableComparator** operators = comparators->GetData();
    CUfunction kernel;
    CU_SAFE_CALL( cuModuleGetFunction( &kernel, *module, functionName ) );

    void *args[] =
    { &input, &leftCount, &rightCount, &tupleNum, &left_unmatched_flag, &right_unmatched_flag, &constValues, &operators, &left_output, &right_output,
            &output_count };

    int numThreads = 256;
    int numBlocks = ( tupleNum + numThreads - 1 ) / numThreads;
    CUresult res = cuLaunchKernel( kernel, numBlocks, 1, 1,    // grid dim
            numThreads, 1, 1,   // block dim
            0, NULL,             // shared mem and stream
            args, 0 );           // arguments
    CU_SAFE_CALL( res );
    CU_SAFE_CALL( cuCtxSynchronize() );
    DestroyComparators( comparators );
    // LOG( INFO ) << "CallKernel gpu time: " << m_ctx->timer_end();
}

void AriesDynamicKernelManager::CallKernel( const vector< CUmoduleSPtr >& modules,
                                            const char* functionName,
                                            const AriesColumnDataIterator *input,
                                            const int32_t* associated,
                                            const int32_t* groups,
                                            const int32_t *group_size_prefix_sum,
                                            int32_t group_count,
                                            int32_t tupleNum,
                                            const int8_t** constValues,
                                            const vector< AriesDynamicCodeComparator >& items,
                                            int8_t *output ) const
{
    ARIES_ASSERT( !modules.empty(), "CUDA module for " + string( functionName ) + " is empty, no dynamic code or no compiling for it?" );
    // m_ctx->timer_begin();
    CUdevice dev; // = m_ctx->active_device_id();
    cudaGetDevice( &dev );
    ARIES_ASSERT( dev < modules.size(),
            "CUDA module for device " + std::to_string( dev ) + " is empty, no dynamic code or no compiling for it?" );
    CUmoduleSPtr module = modules[dev];

    AriesArraySPtr< CallableComparator* > comparators = CreateInComparators( module, items );
    CallableComparator** operators = comparators->GetData();
    CUfunction kernel;
    CU_SAFE_CALL( cuModuleGetFunction( &kernel, *module, functionName ) );

    void *args[] =
    { &input, &associated, &groups, &group_size_prefix_sum, &group_count, &tupleNum, &constValues, &operators, &output };

    int numThreads = 256;
    int numBlocks = ( tupleNum + numThreads - 1 ) / numThreads;
    CUresult res = cuLaunchKernel( kernel, numBlocks, 1, 1,    // grid dim
            numThreads, 1, 1,   // block dim
            0, NULL,             // shared mem and stream
            args, 0 );           // arguments
    CU_SAFE_CALL( res );
    CU_SAFE_CALL( cuCtxSynchronize() );
    DestroyComparators( comparators );
    // LOG( INFO ) << "CallKernel gpu time: " << m_ctx->timer_end();
}

void AriesDynamicKernelManager::CallKernel( const vector< CUmoduleSPtr >& modules,
                                            const char *functionName,
                                            const AriesColumnDataIterator *input,
                                            int tupleNum,
                                            const int8_t** constValues,
                                            const vector< AriesDynamicCodeComparator >& items,
                                            int8_t *output ) const
{
    ARIES_ASSERT( !modules.empty(), "CUDA module for " + string( functionName ) + " is empty, no dynamic code or no compiling for it?" );
//     m_ctx->timer_begin();
    #ifdef ARIES_PROFILE
            aries::CPU_Timer t;
            t.begin();
    #endif
    CUdevice dev; // = m_ctx->active_device_id();
    cudaGetDevice(&dev);
    ARIES_ASSERT( dev < modules.size(),
            "CUDA module for device " + std::to_string( dev ) + " is empty, no dynamic code or no compiling for it?" );
    CUmoduleSPtr module = modules[dev];
    AriesArraySPtr< CallableComparator* > comparators = CreateInComparators( module, items );
    CallableComparator** operators = comparators->GetData();
    CUfunction kernel;
    CU_SAFE_CALL( cuModuleGetFunction( &kernel, *module, functionName ) );

    void *args[] =
    { &input, &tupleNum, &constValues, &operators, &output };

    int numThreads = 256;
    int numBlocks = ( tupleNum + numThreads - 1 ) / numThreads;
    CUresult res = cuLaunchKernel( kernel, numBlocks, 1, 1,    // grid dim
            numThreads, 1, 1,   // block dim
            0, NULL,             // shared mem and stream
            args, 0 );           // arguments
    CU_SAFE_CALL( res );
    CU_SAFE_CALL( cuCtxSynchronize() );
    DestroyComparators( comparators );
#ifdef ARIES_PROFILE
    long long kernel_time = t.end();
    LOG( INFO ) << "CallKernel gpu time: " << kernel_time;
#endif
//     LOG( INFO ) << "CallKernel gpu time: " << m_ctx->timer_end();
}


__global__ void DestroyComparatorsKernel(CallableComparator** data, size_t itemCount)
{
        int tid = threadIdx.x + blockDim.x * blockIdx.x;
        if (tid<itemCount) delete data[tid];
}

void AriesDynamicKernelManager::DestroyComparators( AriesArraySPtr< CallableComparator* > comparators ) const
{
    CallableComparator** data = comparators->GetData();
    size_t itemCount = comparators->GetItemCount();
    if( itemCount > 0 )
    {
        int block = (itemCount + 31) / 32;
        DestroyComparatorsKernel<<<block, 32>>>(data, itemCount);
        // auto k = [=] ARIES_DEVICE(int index)
        // {
        //     for( int i = 0; i < itemCount; ++i )
        //     delete data[i];
        // };
        // transform< launch_box_t< arch_52_cta< 1, 1 > > >( k, 1, *m_ctx );
        // m_ctx->synchronize();
    }
}

AriesArraySPtr< CallableComparator* > AriesDynamicKernelManager::CreateInComparators( CUmoduleSPtr module,
        const vector< AriesDynamicCodeComparator >& items ) const
{
    size_t itemCount = items.size();
    AriesArraySPtr< CallableComparator* > result = std::make_shared< AriesArray< CallableComparator* > >( itemCount );

    if( itemCount > 0 )
    {
        AriesManagedArray< AriesKernelParamInfo > params( itemCount );
        AriesKernelParamInfo* paramData = params.GetData();
        int i = 0;
        for( const auto& item : items )
        {
            auto& info = paramData[i++];
            info.Data = item.LiteralBuffer->GetData();
            info.Count = item.LiteralBuffer->GetItemCount();
            info.Len = item.Type.GetDataTypeSize();
            info.Type = item.Type.DataType.ValueType;
            info.HasNull = item.Type.HasNull;
            info.OpType = item.OpType;
        }
        CallableComparator** comparators = result->GetData();

        CUfunction kernel;
        CU_SAFE_CALL( cuModuleGetFunction( &kernel, *module, "KernelCreateInComparator" ) );

        params.PrefetchToGpu();
        void *args[] =
        { &paramData, &itemCount, &comparators };
        CUresult res = cuLaunchKernel( kernel, 1, 1, 1,    // grid dim
                1, 1, 1,   // block dim
                0, NULL,             // shared mem and stream
                args, 0 );           // arguments
        CU_SAFE_CALL( res );
        CU_SAFE_CALL( cuCtxSynchronize() );
    }

    return result;
}

END_ARIES_ACC_NAMESPACE
