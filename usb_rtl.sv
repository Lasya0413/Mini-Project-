module usb_packet_generator (
    input wire clk,             // 48 MHz USB clock
    input wire reset,           // Active-high reset
    input wire [1:0] pkt_type,  // Packet type: 00=OUT, 01=IN, 10=SOF, 11=DATA
    input wire [6:0] addr,      // Device address
    input wire [3:0] endp,      // Endpoint number
    input wire [7:0] data_in,   // Data to send (for DATA packets)
    input reg  data_valid,      // Data valid signal
    output reg usb_dp,          // USB D+ line
    output reg usb_dm,          // USB D+ line
    output reg tx_enable,       // Transmission active
    output reg pkt_complete     // Packet transmission complete
);

// USB Packet IDs (PIDs)
localparam [3:0] 
    PID_OUT  = 4'b0001,
    PID_IN   = 4'b1001,
    PID_SOF  = 4'b0101,
    PID_DATA = 4'b0011,
    PID_ACK  = 4'b0010,
    PID_NAK  = 4'b1010;
// State machine states
typedef enum {
    IDLE,
    SYNC,
    PID,
    TOKEN_ADDR,
    TOKEN_ENDP,
    TOKEN_CRC5,
    DATA_BYTE,
    DATA_CRC16,
    EOP,
    COMPLETE
} state_t;

reg [3:0] pid;
reg [10:0] token;
reg [15:0] crc16;
reg [4:0] crc5;
//reg [7:0] data_byte;
reg [3:0] bit_count;
reg [3:0] byte_count;
reg [10:0] frame_num;
reg [1:0]delay;
reg sync_en,pid_en,token_en,data_en;
state_t current_state,next_state;

reg last_bit;

// CRC5 calculation
function [4:0] calc_crc5;
    input [10:0] data;
    begin
        calc_crc5[4] = data[10] ^ data[9] ^ data[6] ^ data[5] ^ data[3];
        calc_crc5[3] = data[9] ^ data[8] ^ data[5] ^ data[4] ^ data[2];
        calc_crc5[2] = data[10] ^ data[8] ^ data[7] ^ data[4] ^ data[3] ^ data[1];
        calc_crc5[1] = data[9] ^ data[7] ^ data[6] ^ data[3] ^ data[2] ^ data[0];
        calc_crc5[0] = data[10] ^ data[9] ^ data[8] ^ data[7] ^ data[5] ^ data[4] ^ data[2] ^ data[1] ^ data[0];
    end
endfunction

// CRC16 calculation (updated each bit)
function [15:0] next_crc16;
    input [15:0] current_crc;
    input bit_in;
    begin
        next_crc16[15] = current_crc[14];
        next_crc16[14] = current_crc[13];
        next_crc16[13] = current_crc[12];
        next_crc16[12] = current_crc[11];
        next_crc16[11] = current_crc[10];
        next_crc16[10] = current_crc[9] ^ current_crc[15] ^ bit_in;
        next_crc16[9]  = current_crc[8] ^ current_crc[15] ^ bit_in;
        next_crc16[8]  = current_crc[7];
        next_crc16[7]  = current_crc[6];
        next_crc16[6]  = current_crc[5];
        next_crc16[5]  = current_crc[4] ^ current_crc[15] ^ bit_in;
        next_crc16[4]  = current_crc[3];
        next_crc16[3]  = current_crc[2];
        next_crc16[2]  = current_crc[1] ^ current_crc[15] ^ bit_in;
        next_crc16[1]  = current_crc[0] ^ current_crc[15] ^ bit_in;
        next_crc16[0]  = current_crc[15] ^ bit_in;
    end
endfunction

// NRZI encoding
function [1:0] nrzi_encode;
    input bit_in;       // Current bit to encode (0 or 1)
    input last_bit;     // Previous output state (0=K, 1=J)
    begin
        if (bit_in) begin
            // '1' maintains the current state (no toggle)
            nrzi_encode = {last_bit, ~last_bit}; // J=1/0, K=0/1
        end else begin
            // '0' toggles the state
            nrzi_encode = {~last_bit, last_bit}; // Toggle J↔K
        end
    end
endfunction

// Main state machine
always @(posedge clk or posedge reset) begin
    if (reset) begin
        current_state <= IDLE;
        usb_dp <= 1'b1;
        usb_dm <= 1'b0;
        tx_enable <= 1'b0;
        pkt_complete <= 1'b0;
        last_bit <= 1'b1;
        crc16 <= 16'hFFFF;
        crc5 <= 5'b0;
        bit_count <= 0;
        byte_count <= 0;
        delay<=0;
       // sync_en<=0;
        //pid_en<=0;
        //token_en<=0;
        //data_en<=0;
    end else begin
        current_state <= next_state;
        
        case (current_state)
            IDLE: begin
                usb_dp <= 1'b1;
                usb_dm <= 1'b0;
               // tx_enable<= 1'b0;
                pkt_complete <= 1'b0;
                last_bit <= 1'b1;
                crc16 <= 16'hFFFF;
                tx_enable<=1;
                
                // Set PID based on packet type
                case (pkt_type)
                    2'b00: pid <= PID_OUT;
                    2'b01: pid <= PID_IN;
                    2'b10: pid <= PID_SOF;
                    2'b11: pid <= PID_DATA;
                endcase
                
                // Prepare token field for non-DATA packets
                if (pkt_type != 2'b11) begin
                    if (pkt_type == 2'b10) begin // SOF packet
                        token <= {frame_num, 5'b0}; // 11-bit frame number + 5-bit CRC
                        $display("----SOF----token:%b,frame:%b",token,frame_num);
                    end else begin // OUT or IN packet
                        token <= {endp, addr, 5'b0}; // Endpoint + address + CRC5
                        $display("-----IN/OUT----token:%b,frame:%b",token,frame_num);
                    end
                end
            end
            
           SYNC: begin
                // Send SYNC pattern (0x80)
                if (bit_count < 7) begin
                    sync_en<=1'b1;
                    {usb_dp, usb_dm} <= nrzi_encode(1'b0, last_bit);
                    last_bit <= nrzi_encode(1'b0, last_bit)[0];
                    bit_count <= bit_count + 1;
                end else begin
                    {usb_dp, usb_dm} <= nrzi_encode(1'b1, last_bit); // Last SYNC bit is '1'
                    last_bit <= nrzi_encode(1'b1, last_bit)[0];
                    bit_count <= 0;
                    sync_en<=1'b0;
                end
                tx_enable <= 1'b1;
                
               end
               
              PID: begin
                 // Send PID (4 bits + complement)
                 if (bit_count < 4) begin
                  pid_en<=1'b1;
                 {usb_dp, usb_dm} <= nrzi_encode(pid[bit_count], last_bit);
                 last_bit <= nrzi_encode(pid[bit_count], last_bit)[0];
                 bit_count <= bit_count + 1;
                 end 
                 else if (bit_count <7) begin  // Changed from 7 to 8 to cover all complement bits
                   {usb_dp,usb_dm} <= nrzi_encode(~pid[bit_count-4], last_bit);
                   last_bit <= nrzi_encode(~pid[bit_count-4], last_bit)[0];
                   bit_count <= bit_count + 1;
                 end 
                 else begin
                  {usb_dp, usb_dm} <= nrzi_encode(~pid[3], last_bit);
                   last_bit <= nrzi_encode(~pid[3], last_bit)[0];
                   bit_count <= 0;
                   pid_en<=1'b0;
                 end
                 end

                            
                          
             TOKEN_ADDR: begin
                // Send address (7 bits) + endpoint (4 bits)
                if (bit_count < 7) begin
                    token_en<=1'b1;
                    {usb_dp, usb_dm} <= nrzi_encode(addr[bit_count], last_bit);
                    last_bit <= nrzi_encode(addr[bit_count], last_bit)[0];
                    bit_count <= bit_count + 1;
                end else if (bit_count < 10) begin
                    {usb_dp, usb_dm} <= nrzi_encode(endp[bit_count-7], last_bit);
                    last_bit <= nrzi_encode(endp[bit_count-7], last_bit)[0];
                    bit_count <= bit_count + 1;
                                        //$display("----bit_count:%d",bit_count);
                end else begin
                    //{usb_dp, usb_dm} <= nrzi_encode(endp[3], last_bit);
                    //last_bit <= nrzi_encode(endp[3], last_bit)[0];
                    bit_count<=0;
                    token_en=1'b0;

                    end
                end
            
            
            TOKEN_CRC5: begin
                // Send 5-bit CRC for token
                if (bit_count < 4) begin
                    {usb_dp, usb_dm} <= nrzi_encode(crc5[bit_count], last_bit);
                    last_bit <= nrzi_encode(crc5[bit_count], last_bit)[0];
                    bit_count <= bit_count + 1;
                end else begin
                    {usb_dp,usb_dm} <= nrzi_encode(crc5[bit_count], last_bit);
                    last_bit <= nrzi_encode(crc5[bit_count], last_bit)[0];
                    bit_count <= 0;
                end
            end
            
            DATA_BYTE: begin
                // Send data bytes (8 bits each)
                if (byte_count < 8) begin
                    if (data_valid) begin
                        data_en<=1'b1;
                        if (bit_count < 7) begin
                            {usb_dp, usb_dm} <= nrzi_encode(data_in[bit_count], last_bit);
                            last_bit <= nrzi_encode(data_in[bit_count], last_bit)[0];
                            crc16 <= next_crc16(crc16, data_in[bit_count]);
                            bit_count <= bit_count + 1;
                           // $display("Sending data bit %d: %b, byte_count: %d", bit_count, data_in[bit_count], byte_count);
                        end else begin
                            bit_count <= 0;
                            byte_count <= byte_count + 1;
                            data_en<=1'b0;
                          //  $display("Finished byte %d", byte_count);
                        end
                    end
                end else begin
                    bit_count <= 0;
                    byte_count <= 0;
                end            end
            
            DATA_CRC16: begin
                // Send 16-bit CRC for data packet
                if (bit_count < 16) begin
                    {usb_dp, usb_dm} <= nrzi_encode(crc16[bit_count], last_bit);
                    last_bit <= nrzi_encode(crc16[bit_count], last_bit)[0];
                    bit_count <= bit_count + 1;
                end else begin
                    bit_count <= 0;
                end
            end
            
            EOP: begin
                // End of Packet (2 bits SE0 + 1 bit J)
                if (bit_count < 2) begin
                    {usb_dp, usb_dm} <= 2'b00; // SE0
                    bit_count <= bit_count + 1;
                end else begin
                    {usb_dp, usb_dm} <= 2'b10; // J state
                    bit_count <= 0;
                end
            end
            
            COMPLETE: begin
                pkt_complete <= 1'b1;
                tx_enable <= 1'b0;
               if (delay < 1) begin
                   delay <= delay + 1; // Add delay to ensure tx_enable stays low
               end 
               else begin
                   delay <= 0;
               end           
               end
        endcase
    end
end

// Next state logic
always @(*) begin
    case (current_state)
        IDLE: next_state = SYNC;
        SYNC: next_state = (bit_count == 7) ? PID : SYNC;
        PID: next_state = (bit_count == 7) ? 
                         ((pkt_type == 2'b11) ? DATA_BYTE : TOKEN_ADDR) : PID;
        TOKEN_ADDR: next_state = (bit_count == 10) ? TOKEN_CRC5 : TOKEN_ADDR;
        TOKEN_CRC5: next_state = (bit_count == 4) ? EOP : TOKEN_CRC5;
        DATA_BYTE: next_state = (!data_valid || byte_count == 8) ? DATA_CRC16 : DATA_BYTE;
        DATA_CRC16: next_state = (bit_count == 15) ? EOP : DATA_CRC16;
        EOP: next_state = (bit_count == 2) ? COMPLETE : EOP;
        COMPLETE: next_state= (delay == 1) ? IDLE : COMPLETE;
        default: next_state = IDLE;
    endcase
end

endmodule






