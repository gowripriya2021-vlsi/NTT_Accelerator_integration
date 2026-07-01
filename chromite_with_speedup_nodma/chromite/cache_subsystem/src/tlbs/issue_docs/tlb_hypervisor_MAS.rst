#########
TLB- MAS
#########

The doc foucused on development of TLB for hypervisor and its develelopment divided into different version each 
having some more features that other 

There are two types of TLB that are supported in chromite : `set_associative` and `fully_associative`. We will 
be foucusing of fully associative TLB only

THe purpose of TLB is to cache the translation of GVA to HPA (here). So playing the scenarion of what will happen 
First the core will generate a virtual address, now the virtual address can be from any Virtulized OSs, and it can 
corresponds to any address space in that virtual address so for that we have VMID field in `hgatp` CSR to identify the 
virtual OS the address is coming from and we have `asid`  in `vsatp` CSR which will tell which address space the address
corresponds to.

Upon recieving the request inside TLB the core expects the translated physical address from the TLB. Now the TLB will 
look at the request now this can be a transparent translation or a non transparent translation 

for a transparent translation there are few condition for the tranparent translation 
1. HS-mode(V=0) && satp.mode == 0 or privilage is machine
2. VS-mode(V=1) VSSATP == 0 and  HGATP == 0

if either one of the conditions are true then the TLB will respond with the virtual address it came with

if its not a transparent translation then the tlb will lookup for that VPN and there can be a hit or a miss. For a Hit 
then it performs fault checks (<Describe the checks used for the fault>) if there is no fault then it sends the correspondng ppn (hpa) to the core as part of the response if there is a fult then make the core aware of the fault and the cause of the fault. 

if it a miss then it sends the request to ptwalk in search for HPA, the response form PTWALK will get a translated address

TLBs entries field
===================

- GVA 
- GPA : for mtval2
- GPA permission 
- HPA 
- HPA permission 
- VMID
- ASID
- pagemask : for storing TLB entries of different page size
- V bit 

the cheks for fault will differ of the fact that what kind of tranlation it was (HS-mode or VS/VU mode) which will be decided by the v bit 
in the tlb entry. The check will only be done on the HPA permission bits as this is the final translated address

also GPA is there if there is any falut (guest page fault) then we have to send the GPA value to the CORE<<< ASK AARJUN??????>>>>> GPA permission 

also will the test change based on different mode of VSSatp and HGATP """"?



Version 1 TLB
==============

The fence operation in version 1 have very simple algorithrm it just clears out all the tLB cached entries with 
no conditions whenever any kind of fence in encountered. it can be implented simply by clearing all the entries inside

Version 2 TLB
==============

Here we will also store the vssatp and hgate mode the translation was done, and v bit also its significance it discussed further1

According to my understanding the HFENCE and SFENCE mentioned in the documentation will corresponds to different condition of the 
translation which arise from the different permutation of vssatp.mode and hgatp.mode 

1. VSSATP == 0 and  HGATP == 0 : if this is the case then its a no translation case so no effect

2. VSSATP == 0 and  HGATP != 0 : if this is the case then HFENCE.GVMA is responsible fence the TLB entry corresponding to this condition  	

3. VSSATP != 0 and  HGATP == 0 : if this is the case then HFENCE.VVMA is responsible fence the TLB entry corresponding to this condition

4. VSSATP != 0 and  HGATP != 0 : if this is the case then SFENCE.VMA is responsible fence the TLB entry corresponding to this condition
   also the SFENCE will also depende on condition of V bit
   for request.Sfence.V=0 then it will clear only entries that are in TLB.V=0 (HS- mode translation)
   for request.Sfence.V=1 then it will clear only entries that are in TLB.V=1 (VS- mode translation)
   
also sfence above will also have different complexitiy based on the rs1 and rs2 register it will either point to a particular entry or
it will give the virtual address and the asid field repectively 

for a sfence in v=1 the asid lookup will be combination of asid and vmid

Version 3 TLB
==============
separate tlb baased on V bit 

Here we will have three different trnslation 
..
 1. to cache GVA to GPA 

2. to cahce GPA to HPA
3. to cahce GVA to HPA : this will be the one taking to the core and get the core directly what it needs

The TLBs mentioned in 1, 2 will be used by the ptwalk at its intermediate stages this will be most optized in terms of working not sure about the area and hardware, tho acc to me this will use up the harware but that will not be frequently used by the ptwalk as once the translation get completed their intermediate mem request cache present in the tlb 1, 2 will not be use that much often ...... also to get a pass of this erro what we can do is use small size tlb here as these will be store less number of entrins ans will get updated after easch translation 

BUt implementing above will come at a cost as now ptwalk module has to be re=written keeping in the mind about these sdfa






