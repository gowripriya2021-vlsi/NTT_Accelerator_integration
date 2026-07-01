#include<iostream>
#include<stdlib.h>
#include<string>
#include<vector>

#include <verilated.h>

#include "elfio/elfio.hpp"
#include "elfio/elf_types.hpp"

#pragma GCC diagnostic ignored "-Wwrite-strings"
extern "C" {
unsigned long load_elf(unsigned long, unsigned long , char *);
unsigned long read_f(unsigned long, unsigned long);
void write_f(unsigned long, unsigned long, unsigned long, unsigned char);
}
/* extern char * get_plus_arg(char *aname); */
const char * get_plus_arg(char *aname){
    const char *arg = Verilated::commandArgsPlusMatch(aname+1);
    if(arg && 0<strcmp(arg,aname)){
        auto arglen = strlen(arg)-strlen(aname);
        char *res = (char *) malloc(arglen);
        strncpy(res,arg+strlen(aname)+1,arglen);
        return arg+strlen(aname)+1;
    }
    else{
        return NULL;
    }
}

char *arg = "+elf";

/* extern { */

class memtif{

    unsigned long  *ptr;
    unsigned long  size,base;
    std::string name;
    public:
        memtif(unsigned long  *obj, unsigned long addr, unsigned long  sz, std::string str){
            ptr = obj;
            size = sz;
            name = str;
            base = addr;
        }
        ~memtif(){
            free(ptr);
        }
        unsigned long  read(unsigned long  addr){
            unsigned long idx = addr;
            unsigned long bptr = ((unsigned long) ptr) + idx;
            unsigned long val;
            unsigned char *start =(unsigned char *) (bptr);
            unsigned char *wr_ptr = (unsigned char*)&val;

            if(idx+sizeof(unsigned long )<=size){
                for(auto i=0;i<sizeof(unsigned long);++i)
                    *(wr_ptr++) = *(start++);
                return val;
            }
            else{
                std::cerr<<"Illegal access to "<<name<< std::hex<<addr <<" \n";
                return 0;
            }
        }
        void write(unsigned long  addr, unsigned long  val, unsigned char wstrb){
            /* *(ptr +(addr-base)) = val; */
            unsigned long idx = addr;
            unsigned long bptr = ((unsigned long) ptr) + idx;
            unsigned char *start =(unsigned char *) (bptr);
            unsigned char *wr_ptr = (unsigned char*)&val;
            if(idx+sizeof(unsigned long)<=size)
                for(auto i=0;i<sizeof(unsigned long);i++){
                if(((wstrb>>i)&1) == 1)
                    *(start) = *(wr_ptr);
                start++;
                wr_ptr++;
                }
            else{
                std::cerr<<"Illegal access to "<<name<<"\n";
            }
        }
};

unsigned long  read_f(unsigned long ptr_val,unsigned long  addr){
    memtif *ptr = (memtif *)ptr_val;
    return ptr->read(addr);
}

void write_f(unsigned long ptr_val, unsigned long  addr, unsigned long  val,unsigned char wstrb){
    // putchar intercept: offset 0x1008 = 0x80001008 - 0x80000000
    if (addr == 0x1008UL) { char c = (char)(val & 0xFF); fputc(c,stdout); fflush(stdout); return; }
    // exit intercept: offset 0x1000 = tohost at 0x80001000
    if (addr == 0x1000UL && val != 0) { exit(0); }
    memtif *ptr = (memtif *)ptr_val;
    ptr->write(addr,val,wstrb);
}

unsigned long load_elf(unsigned long base, unsigned long size, char* debug){
        using namespace ELFIO;
        elfio reader;
        auto fname = get_plus_arg(arg);
        if (fname == NULL){
            std::cerr<<"Error. ELF file path not specified."<<std::endl;
            return 0;
        }
        // Check if file name exists
        if(!reader.load(fname))
        {
            std::cerr<<"Error openning elf file: "<<fname<<std::endl;
            return 0;
        }
        auto machine = reader.get_machine();
        // Check if RISCV ELF
        if(not(machine == EM_NONE or machine == EM_RISCV)){
            std::cerr<<"Unsupported elf. Machine: "<< machine << " "<<std::endl;
            return 0;
        }
        // Check if Little Endian encoding in elf.
        if(not(reader.get_encoding()==ELFDATA2LSB)){
            std::cerr<<"Unsupported elf encoding.\n";
            return 0;
        }
        // Setup Memory
        unsigned char  *ptr = (unsigned char *) calloc(size/sizeof(unsigned long ), sizeof(unsigned long ));
        memtif *mem_obj = new memtif((unsigned long *)ptr,base,size,debug);
        Elf_Half seg_num = reader.segments.size();
        for (int i = 0; i<seg_num; ++i){
            const segment* pseg = reader.segments[i];
            auto sz_seg = pseg->get_memory_size();
            auto addr_seg = pseg->get_physical_address();
            if(addr_seg>=base && sz_seg <= size){
                memcpy(ptr+(addr_seg-base),pseg->get_data(),pseg->get_file_size());
            }
        }
        unsigned long ptr_val = (unsigned long)mem_obj;
        return ptr_val;
}
ELFIO::Elf64_Addr get_symbol(ELFIO::elfio *reader, std::string sym) {

    using namespace ELFIO;
    Elf_Half sec_num = reader->sections.size();
    for ( int i = 0; i < sec_num; ++i ) {
        section* psec = reader->sections[i];
        // Check section type
        if ( psec->get_type() == SHT_SYMTAB ) {
            const symbol_section_accessor symbols( *reader, psec );
            for ( unsigned int j = 0; j < symbols.get_symbols_num(); ++j ) {
                std::string   name;
                Elf64_Addr    value;
                Elf_Xword     size;
                unsigned char bind;
                unsigned char type;
                Elf_Half      section_index;
                unsigned char other;

                // Read symbol properties
                symbols.get_symbol( j, name, value, size, bind, type,
                                    section_index, other );
                if(name==sym)
                    return value;
                /* std::cout << j << " " << name << " " << value << std::endl; */
            }
        }
    }
    return 0;

}
/* unsigned long * get_symbol(std::string fname, std::string sym){ */
/*         using namespace ELFIO; */
/*         elfio reader; */
/*         // Check if file name exists */
/*         if(!reader.load(fname)) */
/*         { */
/*             std::cerr<<"Error openning elf file: "<<fname<<std::endl; */
/*             return NULL; */
/*         } */
/*         auto machine = reader.get_machine(); */
/*         // Check if RISCV ELF */
/*         if(not(machine == EM_NONE or machine == EM_RISCV)){ */
/*             std::cerr<<"Unsupported elf. Machine: "<< machine << " "<<std::endl; */
/*             return NULL; */
/*         } */
/*         // Check if Little Endian encoding in elf. */
/*         if(not(reader.get_encoding()==ELFDATA2LSB)){ */
/*             std::cerr<<"Unsupported elf encoding.\n"; */
/*             return NULL; */
/*         } */

/* } */
/* int main(){ */
/*     auto obj = load_elf(0x80000000,0x10000000,"./dut.elf","[0x80000000: 0x8FFFFFFF]: "); */
/*     std::cout << std::hex << obj->read(0); */
/*     delete obj; */
/* } */

/* } */
