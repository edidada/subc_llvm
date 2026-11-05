enable_testing()

add_executable(
  codegen_test
  codegen_test.cc

  ../../lexer.cc 
  ../../type.cc 
  ../../diag_engine.cc
  ../../parser.cc 
  ../../sema.cc 
  ../../scope.cc
  ../../codegen.cc
  ../../eval_constant.cc
)

# Link the monolithic LLVM shared library (libLLVM.so) instead of the static
# .a archives. The conda-forge llvmdev static archives ship an X86 scheduling
# table (X86ReadAdvanceTable) that is broken when linked statically, which makes
# MCJIT segfault inside X86Subtarget construction on x86-64. The shared library
# initializes these tables correctly -- this is exactly how `lli` is linked.
get_filename_component(LLVM_LIB_DIR "${LLVM_DIR}/../.." ABSOLUTE)
find_library(LLVM_DYLIB NAMES LLVM
  PATHS "${LLVM_LIB_DIR}"
  NO_DEFAULT_PATH REQUIRED)
target_link_libraries(
  codegen_test
  GTest::gtest_main
  ${LLVM_DYLIB}
)

include(GoogleTest)
gtest_discover_tests(codegen_test)
