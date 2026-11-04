#pragma once
#include "ast.h"
#include "parser.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Config/llvm-config.h"

class CodeGen : public Visitor, public TypeVisitor {
public:
    CodeGen(std::shared_ptr<Program> p) {
        module = std::make_unique<llvm::Module>(p->fileName, context);
        // Configure the host target triple + DataLayout *before* emitting IR so
        // the IRBuilder produces layout-aware code. An otherwise-empty DataLayout
        // makes MCJIT emit mis-aligned code that segfaults on x86-64 Linux under
        // LLVM 21/22. (main.cc overrides these with the real target afterwards.)
        std::string TT = llvm::sys::getDefaultTargetTriple();
#if LLVM_VERSION_MAJOR >= 21
        llvm::Triple HostTriple(TT);
        module->setTargetTriple(HostTriple);
#else
        module->setTargetTriple(TT);
#endif
        std::string Err;
        const llvm::Target *TheTarget = llvm::TargetRegistry::lookupTarget(
#if LLVM_VERSION_MAJOR >= 21
            HostTriple
#else
            TT
#endif
            , Err);
        if (TheTarget) {
            std::unique_ptr<llvm::TargetMachine> TM(TheTarget->createTargetMachine(
#if LLVM_VERSION_MAJOR >= 21
                HostTriple
#else
                TT
#endif
                , "generic", "", {}, llvm::Reloc::Model::Static,
                {}, llvm::CodeGenOptLevel::None));
            module->setDataLayout(TM->createDataLayout());
        }
        VisitProgram(p.get());
    }

    std::unique_ptr<llvm::Module> &GetModule() {
        return module;
    }

private:
    llvm::Value * VisitProgram(Program *p) override;
    llvm::Value * VisitBlockStmt(BlockStmt *p) override;
    llvm::Value * VisitDeclStmt(DeclStmt *p) override;
    llvm::Value * VisitIfStmt(IfStmt *p) override;
    llvm::Value * VisitForStmt(ForStmt *p) override;
    llvm::Value * VisitContinueStmt(ContinueStmt *p) override;
    llvm::Value * VisitReturnStmt(ReturnStmt *p) override;
    llvm::Value * VisitBreakStmt(BreakStmt *p) override;
    llvm::Value * VisitSwitchStmt(SwitchStmt *p) override;
    llvm::Value * VisitCaseStmt(CaseStmt *p) override;
    llvm::Value * VisitDefaultStmt(DefaultStmt *p) override;
    llvm::Value * VisitDoWhileStmt(DoWhileStmt *p) override;
    llvm::Value * VisitVariableDecl(VariableDecl *decl) override;
    llvm::Value * VisitFuncDecl(FuncDecl *decl) override;
    llvm::Value * VisitBinaryExpr(BinaryExpr *binaryExpr) override;
    llvm::Value * VisitNumberExpr(NumberExpr *factorExpr) override;
    llvm::Value * VisitStringExpr(StringExpr *expr) override;
    llvm::Value * VisitUnaryExpr(UnaryExpr *expr) override;
    llvm::Value * VisitCastExpr(CastExpr *expr) override;
    llvm::Value * VisitSizeOfExpr(SizeOfExpr *expr) override;
    llvm::Value * VisitPostIncExpr(PostIncExpr *expr) override;
    llvm::Value * VisitPostDecExpr(PostDecExpr *expr) override;
    llvm::Value * VisitPostSubscript(PostSubscript *expr) override;
    llvm::Value * VisitPostMemberDotExpr(PostMemberDotExpr *expr) override;
    llvm::Value * VisitPostMemberArrowExpr(PostMemberArrowExpr *expr) override;
    llvm::Value * VisitPostFuncCall(PostFuncCall *expr) override;
    llvm::Value * VisitThreeExpr(ThreeExpr *expr) override;
    llvm::Value * VisitVariableAccessExpr(VariableAccessExpr *factorExpr) override;

    llvm::Type * VisitPrimaryType(CPrimaryType *ty) override;
    llvm::Type * VisitPointType(CPointType *ty) override;
    llvm::Type * VisitArrayType(CArrayType *ty) override;
    llvm::Type * VisitRecordType(CRecordType *ty) override;
    llvm::Type * VisitFuncType(CFuncType *ty) override;
private:
    void Cast(llvm::Value *&val);
    void AssignCast(llvm::Value *&val, llvm::Type *destTy);
    void BinaryArithCast(llvm::Value *&left, llvm::Value *&right);
    llvm::Value *BoolCast(llvm::Value *val);
private:
    void AddLocalVarToMap(llvm::Value *addr, llvm::Type *ty, llvm::StringRef name);
    void AddGlobalVarToMap(llvm::Value *addr, llvm::Type *ty, llvm::StringRef name);
    std::pair<llvm::Value *, llvm::Type *> GetVarByName(llvm::StringRef name);

    void PushScope();
    void PopScope();
    void ClearVarScope();

private:
    llvm::LLVMContext context;
    llvm::IRBuilder<> irBuilder{context};
    std::unique_ptr<llvm::Module> module;
    llvm::Function *curFunc{nullptr};

    llvm::DenseMap<AstNode *, llvm::BasicBlock *> breakBBs;
    llvm::DenseMap<AstNode *, llvm::BasicBlock *> continueBBs;
    llvm::SmallVector<llvm::SwitchInst *> switchStack;

    llvm::SmallVector<llvm::StringMap<std::pair<llvm::Value *, llvm::Type *>>> localVarMap;
    llvm::StringMap<std::pair<llvm::Value *, llvm::Type *>> globalVarMap;
};