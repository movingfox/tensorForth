/*! @file
  @brief
  cueForth Forth Vritual Machine implementation
*/
#include "mmu.h"
#include "eforth.h"
///
/// Forth Virtual Machine operational macros to reduce verbosity
///
#define INT(f)    (static_cast<int>(f+0.5f))    /** cast float to int                        */
#define IU2DU(i)   (static_cast<DU>(i))         /** cast int back to float                   */
#define BOOL(f)   ((f) ? -1 : 0)                /** default boolean representation           */

#define PFA(w)    (dict[(IU)(w)].pfa)           /** PFA of given word id                     */
#define HERE      (mmu.here())                  /** current context                          */
#define XOFF(xp)  (mmu.xtoff((UFP)(xp)))        /** XT offset (index) in code space          */
#define XT(ix)    (mmu.xt(ix))                  /** convert XT offset to function pointer    */
#define SETJMP(a) (mmu.setjmp(a))               /** address offset for branching opcodes     */

#define MRi(ip)   (mmu.ri((IU)(ip)))            /** read an instruction unit from pmem       */
#define MRd(ip)   (mmu.rd((IU)(ip)))            /** read a data unit from pmem               */
#define MWd(ip,d) (mmu.wd((IU)(ip), (DU)(d)))   /** write a data unit to pmem                */
#define MRs(ip)   (mmu.mem((IU)(ip)))           /** pointer to IP address fetched from pmem  */
#define POPi      ((IU)INT(POP()))              /** convert popped DU as an IU               */
#define FIND(s)   (mmu.find(s, compile, ucase))

__GPU__
ForthVM::ForthVM(Istream *istr, Ostream *ostr, MMU *mmu0)
    : fin(*istr), fout(*ostr), mmu(*mmu0), dict(mmu0->dict()) {
        printf("D: dict=%p, mem=%p, vss=%p\n", dict, mmu.mem(0), mmu.vss(blockIdx.x));
}
///
/// Forth inner interpreter (colon word handler)
///
__GPU__ char*
ForthVM::next_idiom()  {                            /// get next idiom from input stream
    fin >> idiom; return idiom;
}
__GPU__ char*
ForthVM::scan(char c) {
    fin.get_idiom(idiom, c); return idiom;
}
__GPU__ void
ForthVM::nest() {
    int dp = 0;                                      /// iterator depth control
    while (dp >= 0) {
        IU ix = MRi(IP);                            /// fetch opcode
        while (ix) {                                 /// fetch till EXIT
            IP += sizeof(IU);
            if (ix & 1) {
                rs.push(WP);                         /// * setup callframe (ENTER)
                rs.push(IP);
                IP = ix & ~0x1;                      /// word pfa (def masked)
                dp++;                                /// go one level deeper
            }
            else if (ix == NXT) {                    /// DONEXT handler (save 600ms / 100M cycles on Intel)
                if ((rs[-1] -= 1) >= 0) IP = MRi(IP);
                else { IP += sizeof(IU); rs.pop(); }
            }
            else (*(FPTR)XT(ix))(ix);                /// * execute primitive word
            ix = MRi(IP);                           /// * fetch next opcode
        }
        if (dp-- > 0) {                              /// pop off a level
            IP = rs.pop();                           /// * restore call frame (EXIT)
            WP = rs.pop();
        }
        yield();                                     ///> give other tasks some time
    }
}
///
/// Dictionary compiler proxy macros to reduce verbosity
///
__GPU__ __INLINE__ void ForthVM::add_iu(IU i) { mmu.add((U8*)&i, sizeof(IU)); }
__GPU__ __INLINE__ void ForthVM::add_du(DU d) { mmu.add((U8*)&d, sizeof(DU)); }
__GPU__ __INLINE__ void ForthVM::add_str(IU op, const char *s) {
    int sz = STRLENB(s)+1; sz = ALIGN2(sz);
    mmu.add((U8*)&op, sizeof(IU));
    mmu.add((U8*)s, sz);
}
__GPU__ __INLINE__ void ForthVM::add_w(IU w) {
    Code &c = dict[w];
    IU   ip = c.def ? (c.pfa | 1) : (w==EXIT ? 0 : XOFF(c.xt));
    add_iu(ip);
    printf("add_w(%d) => %4x:%p %s\n", w, ip, c.xt, c.name);
}
__GPU__ __INLINE__ void ForthVM::call(IU w) {
    Code &c = dict[w];
    if (c.def) { WP = w; IP = c.pfa; nest(); }
    else (*(FPTR)(((UFP)c.xt) & ~0x3))(w);
}
///==============================================================================
///
/// debug functions
///
__GPU__ __INLINE__ void ForthVM::dot_r(int n, DU v) { fout << setw(n) << v; }
__GPU__ __INLINE__ void ForthVM::ss_dump(int n) {
    ss[CUEF_SS_SZ-1] = top;        // put top at the tail of ss (for host display)
    fout << opx(OP_SS, n);
}
///
/// global memory access macros
///
#define PEEK(a)        (U8)(*(U8*)((UFP)(a)))
#define POKE(a, c)     (*(U8*)((UFP)(a))=(U8)(c))
///
/// dictionary initializer
///
__GPU__ void
ForthVM::init() {
    const Code prim[] = {       /// singleton, build once only
    ///
    /// @defgroup Execution flow ops
    /// @brief - DO NOT change the sequence here (see forth_opcode enum)
    /// @{
    CODE("exit",    WP = rs.pop(); IP = rs.pop()),         // quit current word execution
    CODE("donext",
         if ((rs[-1] -= 1) >= 0) IP = MRi(IP);
         else { IP += sizeof(IU); rs.pop(); }),
    CODE("dovar",   PUSH(IP); IP += sizeof(DU)),
    CODE("dolit",   PUSH(MRd(IP)); IP += sizeof(DU)),
    CODE("dostr",
        char *s  = (char*)MRs(IP);                        // get string pointer
        int  sz  = STRLENB(s)+1;
        PUSH(IP); IP += ALIGN2(sz)),
    CODE("dotstr",
        char *s  = (char*)MRs(IP);                        // get string pointer
        int  sz  = STRLENB(s)+1;
        fout << s;  IP += ALIGN2(sz)),                     // send to output console
    CODE("branch" , IP = MRi(IP)),                        // unconditional branch
    CODE("0branch", IP = POP() ? IP + sizeof(IU) : MRi(IP)), // conditional branch
    CODE("does",                                           // CREATE...DOES... meta-program
         IU ip = PFA(WP);
         while (MRi(ip) != DOES) ip++;                    // find DOES
         while (MRi(ip)) add_iu(MRi(ip))),               // copy&paste code
    CODE(">r",   rs.push(POP())),
    CODE("r>",   PUSH(rs.pop())),
    CODE("r@",   PUSH(rs[-1])),
    /// @}
    /// @defgroup Stack ops
    /// @brief - opcode sequence can be changed below this line
    /// @{
    CODE("dup",  PUSH(top)),
    CODE("drop", top = ss.pop()),
    CODE("over", PUSH(ss[-1])),
    CODE("swap", DU n = ss.pop(); PUSH(n)),
    CODE("rot",  DU n = ss.pop(); DU m = ss.pop(); ss.push(n); PUSH(m)),
    CODE("pick", DU i = top; top = ss[-i]),
    /// @}
    /// @defgroup Stack ops - double
    /// @{
    CODE("2dup", PUSH(ss[-1]); PUSH(ss[-1])),
    CODE("2drop",ss.pop(); top = ss.pop()),
    CODE("2over",PUSH(ss[-3]); PUSH(ss[-3])),
    CODE("2swap",
        DU n = ss.pop(); DU m = ss.pop(); DU l = ss.pop();
        ss.push(n); PUSH(l); PUSH(m)),
    /// @}
    /// @defgroup FPU/ALU ops
    /// @{
    CODE("+",    top += ss.pop()),
    CODE("*",    top *= ss.pop()),
    CODE("-",    top =  ss.pop() - top),
    CODE("/",    top =  ss.pop() / top),
    CODE("mod",  top =  fmod(ss.pop(), top)),          /// fmod = x - int(q)*y
    CODE("*/",   top =  ss.pop() * ss.pop() / top),
    CODE("/mod",
        DU n = ss.pop(); DU t = top;
        ss.push(fmod(n, t)); top = round(n / t)),
    CODE("*/mod",
        DU n = ss.pop() * ss.pop();  DU t = top;
        ss.push(fmod(n, t)); top = round(n / t)),
    CODE("and",  top = IU2DU(INT(ss.pop()) & INT(top))),
    CODE("or",   top = IU2DU(INT(ss.pop()) | INT(top))),
    CODE("xor",  top = IU2DU(INT(ss.pop()) ^ INT(top))),
    CODE("abs",  top = abs(top)),
    CODE("negate", top = -top),
    CODE("max",  DU n=ss.pop(); top = (top>n)?top:n),
    CODE("min",  DU n=ss.pop(); top = (top<n)?top:n),
    CODE("2*",   top *= 2),
    CODE("2/",   top /= 2),
    CODE("1+",   top += 1),
    CODE("1-",   top -= 1),
    /// @}
    /// @defgroup Floating Point Math ops
    /// @{
    CODE("int",  top = floor(top)),
    CODE("round",top = INT(top)),
    /// @}
    /// @defgroup Logic ops
    /// @{
    CODE("0= ",  top = BOOL(abs(top) <= DU_EPS)),
    CODE("0<",   top = BOOL(top <  0)),
    CODE("0>",   top = BOOL(top >  0)),
    CODE("=",    top = BOOL(abs(ss.pop() - top) <= DU_EPS)),
    CODE(">",    top = BOOL(ss.pop() >  top)),
    CODE("<",    top = BOOL(ss.pop() <  top)),
    CODE("<>",   top = BOOL(abs(ss.pop() - top) > DU_EPS)),
    CODE(">=",   top = BOOL(ss.pop() >= top)),
    CODE("<=",   top = BOOL(ss.pop() <= top)),
    /// @}
    /// @defgroup IO ops
    /// @{
    CODE("base@",   PUSH(radix)),
    CODE("base!",   fout << setbase(radix = POPi)),
    CODE("hex",     fout << setbase(radix = 16)),
    CODE("decimal", fout << setbase(radix = 10)),
    CODE("cr",      fout << ENDL),
    CODE(".",       fout << POP() << ' '),
    CODE(".r",      IU n = POPi; dot_r(n, POP())),
    CODE("u.r",     IU n = POPi; dot_r(n, abs(POP()))),
    CODE(".f",      IU n = POPi; fout << setprec(n) << POP()),
    CODE("key",     PUSH(next_idiom()[0])),
    CODE("emit",    fout << (char)POPi),
    CODE("space",   fout << ' '),
    CODE("spaces",
         int n = POPi;
         MEMSET(idiom, ' ', n); idiom[n] = '\0';
         fout << idiom),
    /// @}
    /// @defgroup Literal ops
    /// @{
    CODE("[",       compile = false),
    CODE("]",       compile = true),
    IMMD("(",       scan(')')),
    IMMD(".(",      fout << scan(')')),
    CODE("\\",      scan('\n')),
    CODE("$\"",
        const char *s = scan('"')+1;        // string skip first blank
        add_str(DOSTR, s)),                 // dostr, (+parameter field)
    IMMD(".\"",
        const char *s = scan('"')+1;        // string skip first blank
        add_str(DOTSTR, s)),                // dotstr, (+parameter field)
    /// @}
    /// @defgroup Branching ops
    /// @brief - if...then, if...else...then
    /// @{
    IMMD("if", add_w(ZBRAN); PUSH(HERE); add_iu(0)),        // if   ( -- here )
    IMMD("else",                                            // else ( here -- there )
        add_w(BRAN);
         IU h = HERE; add_iu(0); SETJMP(POPi); PUSH(h)),    // set forward jump
    IMMD("then", SETJMP(POPi)),                             // backfill jump address
    /// @}
    /// @defgroup Loops
    /// @brief  - begin...again, begin...f until, begin...f while...repeat
    /// @{
    IMMD("begin",   PUSH(HERE)),
    IMMD("again",   add_w(BRAN);  add_iu(POPi)),            // again    ( there -- )
    IMMD("until",   add_w(ZBRAN); add_iu(POPi)),            // until    ( there -- )
    IMMD("while",   add_w(ZBRAN); PUSH(HERE); add_iu(0)),   // while    ( there -- there here )
    IMMD("repeat",  add_w(BRAN);                            // repeat    ( there1 there2 -- )
        IU t=POPi; add_iu(POPi); SETJMP(t)),                // set forward and loop back address
    /// @}
    /// @defgrouop For loops
    /// @brief  - for...next, for...aft...then...next
    /// @{
    IMMD("for" ,    add_w(TOR); PUSH(HERE)),                // for ( -- here )
    IMMD("next",    add_w(DONEXT); add_iu(POPi)),           // next ( here -- )
    IMMD("aft",                                             // aft ( here -- here there )
        POP(); add_w(BRAN);
        IU h=HERE; add_iu(0); PUSH(HERE); PUSH(h)),
    /// @}
    /// @defgrouop Compiler ops
    /// @{
    CODE(":", mmu.colon(next_idiom()); compile=true),
    IMMD(";", add_w(EXIT); compile = false),
    CODE("variable",                                        // create a variable
        mmu.colon(next_idiom());                            // create a new word on dictionary
        add_w(DOVAR);                                       // dovar (+parameter field)
        add_du(0)),                                         // data storage (32-bit integer now)
    CODE("constant",                                        // create a constant
        mmu.colon(next_idiom());                            // create a new word on dictionary
        add_w(DOLIT);                                       // dovar (+parameter field)
        add_du(POP())),                                     // data storage (32-bit integer now)
    /// @}
    /// @defgroup metacompiler
    /// @brief - dict is directly used, instead of shield by macros
    /// @{
    CODE("exec",  call(POPi)),                              // execute word
    CODE("create",
        mmu.colon(next_idiom());                            // create a new word on dictionary
        add_w(DOVAR)),                                      // dovar (+ parameter field)
    CODE("to",              // 3 to x                       // alter the value of a constant
        int w = FIND(next_idiom());                         // to save the extra @ of a variable
        MWd(PFA(w) + sizeof(IU), POP())),
    CODE("is",              // ' y is x                     // alias a word
        int w = FIND(next_idiom());                         // can serve as a function pointer
        mmu.wi(PFA(POP()), PFA(w))),                        // but might leave a dangled block
    CODE("[to]",            // : xx 3 [to] y ;              // alter constant in compile mode
        IU w = MRi(IP); IP += sizeof(IU);                // fetch constant pfa from 'here'
        MWd(PFA(w) + sizeof(IU), POP())),
    ///
    /// be careful with memory access, especially BYTE because
    /// it could make access misaligned which slows the access speed by 2x
    ///
    CODE("@",     IU w = POPi; PUSH(MRd(w))),                                     // w -- n
    CODE("!",     IU w = POPi; MWd(w, POP())),                                    // n w --
    CODE(",",     DU n = POP(); add_du(n)),
    CODE("allot", DU v = 0; for (IU n = POPi, i = 0; i < n; i++) add_du(v)),       // n --
    CODE("+!",    IU w = POPi; MWd(w, MRd(w)+POP())),                            // n w --
    CODE("?",     IU w = POPi; fout << MRd(w) << " "),                            // w --
    /// @}
    /// @defgroup Debug ops
    /// @{
    CODE("here",  PUSH(HERE)),
    CODE("ucase", ucase = POPi),
    CODE("'",     int w = FIND(next_idiom()); PUSH(w)),
    CODE(".s",    ss_dump(POPi)),
    CODE("words", fout << opx(OP_WORDS)),
    CODE("see",   int w = FIND(next_idiom()); fout << opx(OP_SEE, (IU)w)),
    CODE("dump",  IU n = POPi; IU a = POPi; fout << opx(OP_DUMP, a, n)),
    CODE("forget",
        int w = FIND(next_idiom());
        if (w<0) return;
        IU b = FIND("boot")+1;
        mmu.clear(w > b ? w : b)),
    /// @}
    /// @defgroup System ops
    /// @{
    CODE("peek",  IU a = POPi; PUSH(PEEK(a))),
    CODE("poke",  IU a = POPi; POKE(a, POPi)),
    CODE("clock", PUSH(millis())),
    CODE("delay", delay(POPi)),                                // TODO: change to VM_WAIT
    CODE("bye",   status = VM_STOP),
    CODE("boot",  mmu.clear(FIND("boot") + 1))
    /// @}
    };
    int n = sizeof(prim)/sizeof(Code);
    for (int i=0; i<n; i++) {
        mmu << (Code*)&prim[i];
    }
	for (int i=0; i<n; i++) {
	    printf("%3d> xt=%4x:%p name=%4x:%p %s\n", i,
				XOFF(dict[i].xt), dict[i].fp,
				(dict[i].name - dict[0].name), dict[i].name,
				dict[i].name);            // dump dictionary from device
	}
    NXT = XOFF(dict[DONEXT].xt);         /// cache offset to subroutine address

    printf("init() VM=%p sizeof(Code)=%d\n", this, (int)sizeof(Code));
    status = VM_RUN;
};
///
/// ForthVM Outer interpreter
/// @brief having outer() on device creates branch divergence but
///    + can enable parallel VMs (with different tasks)
///    + can support parallel find()
///    + can support system without a host
///    However, to optimize,
///    + compilation can be done on host and
///    + only call() is dispatched to device
///    + number() and find() can run in parallel
///    - however, find() can run in serial only
///
__GPU__ void
ForthVM::outer() {
    while (fin >> idiom) {                   /// loop throught tib
        printf("%d>> %s => ", blockIdx.x, idiom);
        int w = FIND(idiom);                 /// * search through dictionary
        if (w>=0) {                          /// * word found?
            printf("%4x:%p %s %d\n",
            	dict[w].def ? dict[w].pfa : XOFF(dict[w].xt),
            	dict[w].xt, dict[w].name, w);
            if (compile && !dict[w].immd) {  /// * in compile mode?
                add_w((IU)w);                /// * add found word to new colon word
            }
            else call((IU)w);                /// * execute forth word
            continue;
        }
        // try as a number
        char *p;
        DU n = (STRCHR(idiom, '.'))
                ? STRTOF(idiom, &p)
                : STRTOL(idiom, &p, radix);
        if (*p != '\0') {                    /// * not number
            fout << idiom << "? " << ENDL;   ///> display error prompt
            compile = false;                 ///> reset to interpreter mode
            break;                           ///> skip the entire input buffer
        }
        // is a number
        printf("%f = %08x\n", n, *(U32*)&n);
        if (compile) {                       /// * add literal when in compile mode
            add_w(DOLIT);                    ///> dovar (+parameter field)
            add_du(n);                       ///> store literal
        }
        else PUSH(n);                        ///> or, add value onto data stack
    }
    if (!compile) ss_dump(ss.idx);
}
//=======================================================================================
