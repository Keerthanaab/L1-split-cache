module SplitL1Cache ;
	parameter Sets      		= 'd 2**14; 		                 // sets (16K)
	parameter ByteLines 		= 'd 64;	 		          // Cache lines (64-byte)
	
	parameter AddressBits    	= 'd 32;	 		             // Address bits (32-bit processor) 
    logic 	[AddressBits - 1 :0] Address;                        // Address	
	
	localparam IndexBits 		= $clog2(Sets); 	 			         // Index bits
	logic 	[IndexBits - 1	:0] Index;		                             // Index
	
	localparam ByteOffset 		= $clog2(ByteLines);		 		// Byte select bits
	logic 	[ByteOffset - 1 :0] Byte;		                       // Byte select
	
	localparam TagBits 		    = (AddressBits)-(IndexBits+ByteOffset); 	// Tag bits
	logic 	[TagBits - 1 :0] Tag;			                                // Tag
		
	logic	Mode;					// Mode select
	logic 	Hit;					// to Know Hit or Miss 
	logic	NOT_Valid;				// to know when invalid line is present
	logic 	[3:0] n;				// Instruction code from trace file
	longint CacheIterations = 0;	// No.of Cache accesses
	
    bit 	Flag;	
	typedef enum logic [1:0]{       				
				Invalid 	= 2'b00,
				Shared 		= 2'b01, 
				Modified 	= 2'b10, 
				Exclusive 	= 2'b11	
				} mesi;  //MESI states 
				
	
//-----------------------------Data inputs------------------------------------------------------
	
	parameter DataWay     	= 'd 8;	 		                // Data cache 
	localparam DataWay_bits	= $clog2(DataWay);				// Data select bits 
	int Data_HIT_count  	= 0; 				               // Data Hits
	int Data_MISS_count 	= 0; 				              // Data Misses 
	int Data_READ_count 	= 0; 				             // Cache reads
	int Data_WRITE_count 	= 0; 				            // cache writes
	real Data_HIT_Ratio;			                      // Data Cache Hit ratio
	bit [DataWay_bits - 1 :0]	Data_ways;		 	     // Data ways
	
	
//---------------------Instruction inputs-------------------------------------------------------
	
    parameter InstWay      	   	= 'd 4;	 		      // Instruction Cache
	localparam InstWay_bits		= $clog2(InstWay);    //Instruction select bits 
	int Inst_HIT_count  	    = 0; 		         // Instruction Cache Hits
	int Inst_MISS_count 	    = 0; 		        // Instruction Cache Misses
	int Inst_READ_count 	    = 0; 		       //Instruction Cache reads
	real Inst_HIT_Ratio; 			              // Instruction Cache Hit Ratio
	bit [InstWay_bits - 1 :0]Instruction_ways;		// Instruction ways

	
//--------------------------------- L1 Data Cache ------------------------------------------------			
	typedef struct packed {							
				mesi MESI_bits;
				bit [DataWay_bits-1:0]	LRU_bits;
				bit [TagBits	-1:0] 	TagBits;			 
				} CacheLine_DATA;
CacheLine_DATA [Sets-1:0] [DataWay-1:0] L1_DATA_Cache; 


//---------------------------- L1 Instruction Cache -------------------------------------------

	typedef struct packed {							
				mesi MESI_bits;
				bit [InstWay_bits-1:0]	LRU_bits;
				bit [TagBits	-1:0] 	TagBits;     
				} CacheLine_INSTRUCTION;
CacheLine_INSTRUCTION [Sets-1:0][InstWay-1:0] L1_INSTRUCTION_Cache; 

int	TRACE;					
int	temp_display;

//------------------------  Read instructions from Trace File ------------------------------------ 

initial							
begin
	ClearCache();
    TRACE = $fopen("traceFile.txt" , "r");     // trace file input
   	if ($test$plusargs("USER_MODE")) 
			Mode=0;
    	else
    		Mode=1;
	while (!$feof(TRACE))				//when end of the trace file is not reached
	begin
        temp_display = $fscanf(TRACE, "%h %h\n",n,Address);
        {Tag,Index,Byte} = Address;
    
		case (n) inside
			4'd0:	ReadFromL1DataCache(Tag,Index,Mode);   		
			4'd1:	WritetoL1DataCache (Tag,Index,Mode);
			4'd2: 	InstructionFetch   (Tag,Index,Mode);
			4'd3:	SendInvalidateCommandFromL2Cache(Tag,Index,Mode);   
			4'd4:	DataRequestFromL2Cache (Tag,Index,Mode);
			4'd8:	ClearCache();
			4'd9:	Print_CacheContents_MESIstates();
		endcase			
	end
	$fclose(TRACE);
	Data_HIT_Ratio = (real'(Data_HIT_count)/(real'(Data_HIT_count) + real'(Data_MISS_count))) * 100.00;
	Inst_HIT_Ratio 	= (real'(Inst_HIT_count) /(real'(Inst_HIT_count)  + real'(Inst_MISS_count))) *100.00;
     
 $display("------------------------------------- INSTRUCTION  CACHE STATSITICS ----------------------------------------------------------");
 $display("Instruction Cache Reads      = %d \n Instruction Cache Misses    = %d \n Instruction Cache Hits      = %d \n Instruction Cache Hit Ratio   =  %f \n",Inst_READ_count, Inst_MISS_count, Inst_HIT_count, Inst_HIT_Ratio);
	
	$display("------------------------------------- DATA  CACHE  STATSITICS -----------------------------------------------------------------");
  $display("Data Cache Reads     =  %d\n Data Cache Writes    = %d\n Data Cache Hits      = %d \n Data Cache Misses    = %d \n Data Cache Hit Ratio =   %f\n", Data_READ_count, Data_WRITE_count, Data_HIT_count, Data_MISS_count, Data_HIT_Ratio);
	$finish;
										
end


//-----------------------------Read Data From L1 Cache-----------------------------------------

task ReadFromL1DataCache ( logic [TagBits-1 :0] Tag, logic [IndexBits-1:0] Index, logic Mode); 
	
	Data_READ_count++ ;
	Data_Address_Valid (Index,Tag,Hit,Data_ways);
	
	if (Hit == 1)
	begin
		Data_HIT_count++ ;
		UpdateLRUBits_data(Index, Data_ways );
		L1_DATA_Cache[Index][Data_ways].MESI_bits = (L1_DATA_Cache[Index][Data_ways].MESI_bits == Exclusive) ? Shared : L1_DATA_Cache[Index][Data_ways].MESI_bits ;		
	end
	else
	begin
		Data_MISS_count++ ;
		NOT_Valid = 0;
		If_Invalid_Data (Index , NOT_Valid , Data_ways );
		
		if (NOT_Valid)
		begin
			Data_Allocate_CacheLine(Index,Tag, Data_ways);
			UpdateLRUBits_data(Index, Data_ways );
			L1_DATA_Cache[Index][Data_ways].MESI_bits = Exclusive;   
			
			if (Mode==0)
				$display("Read from L2 address       %d'h%h" ,AddressBits,Address);//Sending data to L2 because modified data will be lost while reset
		end
		else    
		begin
			Eviction_Data(Index, Data_ways);
			Data_Allocate_CacheLine(Index, Tag, Data_ways);
			UpdateLRUBits_data(Index, Data_ways );
			L1_DATA_Cache[Index][Data_ways].MESI_bits = Exclusive;  
			
			if (Mode==1)
			$display("Read from L2 address       %d'h%h" ,AddressBits,Address);
		end
	end	
endtask


//------------------------------Write Data to L1 Data Cache---------------------------------------------------

task WritetoL1DataCache ( logic [TagBits -1 :0] Tag, logic [IndexBits-1:0] Index, logic Mode);
	
	Data_WRITE_count++ ;
	Data_Address_Valid (Index, Tag, Hit, Data_ways);
	
	if (Hit == 1)
	begin
		Data_HIT_count++ ;
		UpdateLRUBits_data(Index, Data_ways );	
		if (L1_DATA_Cache[Index][Data_ways].MESI_bits == Shared)
		begin
			L1_DATA_Cache[Index][Data_ways].MESI_bits = Modified;
			if(Mode==1) 
			$display("Write to L2 address        %d'h%h" ,AddressBits,Address);
		end
		else if(L1_DATA_Cache[Index][Data_ways].MESI_bits == Exclusive)
			L1_DATA_Cache[Index][Data_ways].MESI_bits = Modified;
	end
	else
	begin
		Data_MISS_count++ ;
		If_Invalid_Data(Index , NOT_Valid , Data_ways );
	
		if (NOT_Valid)
		begin
			Data_Allocate_CacheLine(Index,Tag, Data_ways);
			UpdateLRUBits_data(Index, Data_ways );
			L1_DATA_Cache[Index][Data_ways].MESI_bits = Exclusive;
			if (Mode==1)
				$display("Read for ownership from L2 %d'h%h\nWrite to L2 address        %d'h%h ",AddressBits,Address,AddressBits,Address);
		end
		else
		begin
			Eviction_Data(Index, Data_ways);
			Data_Allocate_CacheLine(Index, Tag, Data_ways);
			UpdateLRUBits_data(Index, Data_ways );
			L1_DATA_Cache[Index][Data_ways].MESI_bits = Modified;  
			if (Mode==1) 
				$display("Read for ownership from L2 %d'h%h",AddressBits,Address);
		end
	end	
endtask


//---------------------------------Instruction Fetch---------------------------------------------------------

task InstructionFetch ( logic [TagBits -1 :0] Tag, logic [IndexBits-1:0] Index, logic Mode);
	
	Inst_READ_count++ ;
	Inst_Address_Valid (Index, Tag, Hit, Instruction_ways);
	
	if (Hit == 1)
	begin
		Inst_HIT_count++ ;
		UpdateLRUBits_ins(Index, Instruction_ways );
		L1_INSTRUCTION_Cache[Index][Instruction_ways].MESI_bits = (L1_INSTRUCTION_Cache[Index][Instruction_ways].MESI_bits == Exclusive) ? Shared : L1_INSTRUCTION_Cache[Index][Instruction_ways].MESI_bits	;
	end
	else
	begin
		Inst_MISS_count++ ;
		If_Invalid_Inst(Index ,  NOT_Valid , Instruction_ways );
		
		if (NOT_Valid)
		begin
			Inst_Allocate_Line(Index,Tag, Instruction_ways);
			UpdateLRUBits_ins(Index, Instruction_ways );
			L1_INSTRUCTION_Cache[Index][Instruction_ways].MESI_bits = Exclusive; 
			if (Mode==1)
				$display("Read from L2 address       %d'h%h" ,AddressBits,Address);
		end
		else
		begin
			Eviction_Inst(Index, Instruction_ways);
			Inst_Allocate_Line(Index, Tag, Instruction_ways);
			UpdateLRUBits_ins(Index,  Instruction_ways );
			L1_INSTRUCTION_Cache[Index][Instruction_ways].MESI_bits = Exclusive;         
			if (Mode==1)
				$display("Read from L2 address       %d'h%h" ,AddressBits,Address);
		end
	end
endtask


//-------------------------------Data Request From L2 Cache---------------------------------------------------------


task DataRequestFromL2Cache ( logic [TagBits -1 :0] Tag, logic [IndexBits-1:0] Index, logic Mode); // Data Request from L2 Cache
	
	Data_Address_Valid (Index, Tag, Hit, Data_ways);
	if (Hit == 1)
		case (L1_DATA_Cache[Index][Data_ways].MESI_bits) inside
		
			Exclusive:	L1_DATA_Cache[Index][Data_ways].MESI_bits = Shared;
			Modified :	begin
						L1_DATA_Cache[Index][Data_ways].MESI_bits = Invalid;
						if (Mode==1)
							$display("Return data to L2 address  %d'h%h" ,AddressBits,Address);
					end
		endcase
endtask  
 
//-------------------------Send Invalidate Command From L2 Cache-----------------------------------------------------


task SendInvalidateCommandFromL2Cache ( logic [TagBits -1 :0] Tag, logic [IndexBits-1:0] Index, logic Mode);
	
	Data_Address_Valid (Index, Tag, Hit, Data_ways);
	if (Hit == 1)
	begin
	 	if( Mode==1) //&& (L1_DATA_Cache[Index][Data_ways].MESI_bits == Modified)) 
			$display("Write to L2 address        %d'h%h" ,AddressBits,Address);
		L1_DATA_Cache[Index][Data_ways].MESI_bits = Invalid;
	end
endtask


///////////////////////////////////////////////Data cache////////////////////////////////////////////////////////


//---------------------------- Data Cache line Allocation---------------------------------------------------------


task automatic Data_Allocate_CacheLine (logic [IndexBits -1:0] iIndex, logic [TagBits -1 :0] iTag, ref bit [DataWay_bits-1:0] Data_ways); // Allocacte Cache Line in DATA CACHE
	L1_DATA_Cache[iIndex][Data_ways].TagBits = iTag;
	UpdateLRUBits_data(iIndex, Data_ways);		
endtask


//--------------------- Address Valid task of Data Cache --------------------------------------------


task automatic Data_Address_Valid (logic [IndexBits-1 :0] iIndex, logic [TagBits -1 :0] iTag, output logic Hit , ref bit [DataWay_bits-1:0] Data_ways ); 
	Hit = 0;

	for (int j = 0;  j < DataWay ; j++)
		if (L1_DATA_Cache[iIndex][j].MESI_bits != Invalid) 	
			if (L1_DATA_Cache[iIndex][j].TagBits == iTag)
			begin 
				Data_ways = j;
				Hit = 1; 
				return;
			end			
endtask

//-------------------------------Check for Invalid state of Data cache--------------------------------------------------


task automatic If_Invalid_Data (logic [IndexBits-1:0] iIndex, output logic Invalid, ref bit [DataWay_bits-1:0] Data_ways); // Find invalid Cache line in DATA CACHE
	NOT_Valid =  0;
	for (int i =0; i< DataWay; i++ )
	begin
		if (L1_DATA_Cache[iIndex][i].MESI_bits == Invalid)
		begin
			Data_ways = i;
			NOT_Valid = 1;
			return;
		end
	end
endtask

//-------------------- Eviction line task of Data cache-------------------------------------


task automatic Eviction_Data (logic [IndexBits -1:0] iIndex, ref bit [DataWay_bits-1:0] Data_ways);
	for (int i =0; i< DataWay; i++ )
		if( L1_DATA_Cache[iIndex][i].LRU_bits ==  '0 )
		begin
			if( Mode==1 && (L1_DATA_Cache[iIndex][i].MESI_bits == Modified) )
				$display("Write to L2 address        %d'h%h" ,AddressBits,Address);
			Data_ways = i;
		end
endtask

//-----------------------updating LRU bits for Data cache --------------------------------------


task automatic UpdateLRUBits_data(logic [IndexBits-1:0]iIndex, ref bit [DataWay_bits-1:0] Data_ways ); 
	logic [DataWay_bits-1:0]temp;
	temp = L1_DATA_Cache[iIndex][Data_ways].LRU_bits;
	
	for (int j = 0; j < DataWay ; j=j+1)
		L1_DATA_Cache[iIndex][j].LRU_bits = (L1_DATA_Cache[iIndex][j].LRU_bits > temp) ? L1_DATA_Cache[iIndex][j].LRU_bits - 1'b1 : L1_DATA_Cache[iIndex][j].LRU_bits;
			
	L1_DATA_Cache[iIndex][Data_ways].LRU_bits = '1;
endtask 

/////////////////////////////////////////Instruction cache/////////////////////////////////////////////////////////


//----------------------------Instruction cache line Allocation-------------------------------------------------


task automatic Inst_Allocate_Line (logic [IndexBits -1 :0] iIndex, logic [TagBits -1 :0] iTag, ref bit [InstWay_bits-1:0] Instruction_ways); // Allocacte Cache Line in INSTRUCTION CACHE
	L1_INSTRUCTION_Cache[iIndex][Instruction_ways].TagBits = iTag;
	UpdateLRUBits_ins(iIndex, Instruction_ways);
endtask


// ---------------------   Address valid task of Instruction cache ----------------------------------------


task automatic Inst_Address_Valid (logic [IndexBits-1 :0] iIndex, logic [TagBits -1 :0] iTag, output logic Hit , ref bit [InstWay_bits-1:0] Instruction_ways);
	Hit = 0;

	for (int j = 0;  j < InstWay ; j++)
		if (L1_INSTRUCTION_Cache[iIndex][j].MESI_bits != Invalid) 
			if (L1_INSTRUCTION_Cache[iIndex][j].TagBits == iTag)
			begin 
				Instruction_ways = j;
				Hit = 1; 
				return;
			end
endtask

//------------------------   Check for Invalid state of Instruction cache ----------------------------------

task automatic If_Invalid_Inst (logic [IndexBits - 1:0] iIndex, output logic NOT_Valid, ref bit [InstWay_bits-1:0] Instruction_ways); // Find invalid Cache line in INSTRUCTION CACHE
	NOT_Valid =  0;
	for(int i =0; i< InstWay; i++ )
		if (L1_INSTRUCTION_Cache[iIndex][i].MESI_bits == Invalid)
		begin
			Instruction_ways = i;
			NOT_Valid = 1;
			return;
		end
endtask

//------------------- Eviction line task of Instruction cache ----------------------------

task automatic Eviction_Inst (logic [IndexBits - 1:0] iIndex, ref bit [InstWay_bits-1:0] Instruction_ways);
	for (int i =0; i< InstWay; i++ )
		if( L1_INSTRUCTION_Cache[iIndex][i].LRU_bits == '0 )
		begin
			if( Mode==1 && (L1_INSTRUCTION_Cache[iIndex][i].MESI_bits == Modified) )
					$display("Write to L2 address        %d'h%h" ,AddressBits,Address);				
			Instruction_ways = i;
		end
endtask

//----------------------  Updating LRU bits for instruction cache ----------------------

task automatic UpdateLRUBits_ins(logic [IndexBits-1:0]iIndex, ref bit [InstWay_bits-1:0] Instruction_ways ); 
	logic [InstWay_bits-1:0]temp;
	temp = L1_INSTRUCTION_Cache[iIndex][Instruction_ways].LRU_bits;
	
	for (int j = 0; j < InstWay ; j++)
		L1_INSTRUCTION_Cache[iIndex][j].LRU_bits = (L1_INSTRUCTION_Cache[iIndex][j].LRU_bits > temp) ? L1_INSTRUCTION_Cache[iIndex][j].LRU_bits - 1'b1 : L1_INSTRUCTION_Cache[iIndex][j].LRU_bits;
	
	L1_INSTRUCTION_Cache[iIndex][Instruction_ways].LRU_bits = '1;
endtask 



//-----------------------To Print Cache contents and MESI States-------------------------------------//

task Print_CacheContents_MESIstates();	

$display("-------------------------------  INSTRUCTION CACHE CONTENTS  ---------------------------------- ");
	for(int i=0; i< Sets; i++)
	begin
		for(int j=0; j< InstWay; j++) 
			if(L1_INSTRUCTION_Cache[i][j].MESI_bits != Invalid)
			begin
				if(!Flag)
				begin
					$display("Index = %d'h%h\n",IndexBits,i);
					Flag = 1;
				end
              $display(" Way = %d  ||   Tag = %d'h%h   ||  MESI = %s    ||  LRU =  %d'b%b", j,TagBits, L1_INSTRUCTION_Cache[i][j].TagBits, L1_INSTRUCTION_Cache[i][j].MESI_bits,InstWay_bits,L1_INSTRUCTION_Cache[i][j].LRU_bits);
			end
		Flag = 0;
	end
	$display("--------------------------------END OF INSTRUCTION CACHE---------------------------------------------\n");	
	$display("---------------------------------- DATA CACHE CONTENTS  --------------------------------------------- ");
	
	for(int i=0; i< Sets; i=i+1)
	begin
		for(int j=0; j< DataWay; j=j+1) 
			if(L1_DATA_Cache[i][j].MESI_bits != Invalid)
			begin
				if(!Flag)
				begin
					$display("Index = %d'h%h\n", IndexBits , i );
					Flag = 1;
				end
              $display(" Way = %d || Tag = %d'h%h || MESI = %s   ||   LRU = %d'b%b", j,TagBits,L1_DATA_Cache[i][j].TagBits, L1_DATA_Cache[i][j].MESI_bits,DataWay_bits,L1_DATA_Cache[i][j].LRU_bits);
			end
		Flag = 0;
	end
	$display("-------------------------------- END OF DATA CACHE ----------------------------------------------------------\n\n");
endtask

//------------------------------Clear cache-----------------------------------------------

task ClearCache();
Data_HIT_count    	= 0;
Data_MISS_count 	= 0;
Data_READ_count 	= 0;
Data_WRITE_count    = 0;
	
Inst_HIT_count	    = 0;
Inst_MISS_count 	= 0;
Inst_READ_count 	= 0;
fork
for(int i=0; i< Sets; i=i+1) 
		for(int j=0; j< DataWay; j=j+1) 
			L1_DATA_Cache[i][j].MESI_bits = Invalid;

	for(int i=0; i< Sets; i=i+1) 
		for(int j=0; j< InstWay; j=j+1) 
			L1_INSTRUCTION_Cache[i][j].MESI_bits = Invalid;
join
endtask


endmodule


