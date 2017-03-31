`timescale 1ns/1ns
module main (CLOCK_50,
        KEY,
        SW,
        HEX0,
        HEX1,
        HEX4,
        HEX5,
        // The ports below are for the VGA output.  Do not change.
        VGA_CLK,                        //  VGA Clock
        VGA_HS,                         //  VGA H_SYNC
        VGA_VS,                         //  VGA V_SYNC
        VGA_BLANK_N,                        //  VGA BLANK
        VGA_SYNC_N,                     //  VGA SYNC
        VGA_R,                          //  VGA Red[9:0]
        VGA_G,                          //  VGA Green[9:0]
        VGA_B                           //  VGA Blue[9:0]
        );

    // ------------------------io------------------------
    input CLOCK_50;
    input [3:0] KEY;
    input [2:0] SW;
    output [6:0] HEX0, HEX1, HEX4, HEX5;
   
    // Do not change the following outputs
    output          VGA_CLK;                //  VGA Clock
    output          VGA_HS;                 //  VGA H_SYNC
    output          VGA_VS;                 //  VGA V_SYNC
    output          VGA_BLANK_N;                //  VGA BLANK
    output          VGA_SYNC_N;             //  VGA SYNC
    output  [9:0]   VGA_R;                  //  VGA Red[9:0]
    output  [9:0]   VGA_G;                  //  VGA Green[9:0]
    output  [9:0]   VGA_B;                  //  VGA Blue[9:0]


    // -------------------------var------------------------
    wire [27:0] rateCount;
    wire [7:0] x;
    wire [6:0] y;
    wire [2:0] c_out;
    wire [7:0] score;
    wire [7:0] timeLeft;

    wire reset, go, start, restart;
    wire [4:0] in;
    assign reset = ~SW[0];
    assign start = SW[1];
    assign go = (SW[1]^!KEY[3]^!KEY[2]^!KEY[1]^!KEY[0]);
    assign in = {SW[1], !KEY[3], !KEY[2], !KEY[1], !KEY[0]};

    wire printGrid, printFarmer, printHamster, move;
    wire gridDone, farmerDone, hamsterDone, moveDone;
    wire [7:0] farmerPos, hamsterPos;
    wire [207:0] grid;
    wire [207:0] gridtemp;

    assign grid = {
    16'b1111111111111111,
    16'b1000110001100011,
    16'b1000110001100011,
    16'b1000110001100011,
    16'b1111111111111111,
    16'b1000110001100011,
    16'b1000110001100011,
    16'b1000110001100011,
    16'b1111111111111111,
    16'b1000110001100011,
    16'b1000110001100011,
    16'b1000110001100011,
    16'b1111111111111111
    };



    // Create an Instance of a VGA controller - there can be only one!
    // Define the number of colours as well as the initial background
    // image file (.MIF) for the controller.
    vga_adapter VGA(
            .resetn(reset),
            .clock(CLOCK_50),
            .colour(c_out),
            .x(x),
            .y(y),
            .plot(1'b1),
            // Signals for the DAC to drive the monitor.
            .VGA_R(VGA_R),
            .VGA_G(VGA_G),
            .VGA_B(VGA_B),
            .VGA_HS(VGA_HS),
            .VGA_VS(VGA_VS),
            .VGA_BLANK(VGA_BLANK_N),
            .VGA_SYNC(VGA_SYNC_N),
            .VGA_CLK(VGA_CLK));
        defparam VGA.RESOLUTION = "160x120";
        defparam VGA.MONOCHROME = "FALSE";
        defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
        defparam VGA.BACKGROUND_IMAGE = "black.mif";


    // Instansiate FSM control
    control c0(CLOCK_50, reset, timeLeft, gridDone, farmerDone, hamsterDone, moveDone, go, start, printGrid, printFarmer, printHamster, restart, move);

    // Instansiate datapath
    datapath d0(CLOCK_50, reset, printGrid, printFarmer, printHamster, restart, move, in, grid, gridtemp, x, y, c_out, gridDone, farmerDone, hamsterDone, moveDone, farmerPos, hamsterPos, score);

    RateDivider rd0 (28'h2faf080, reset, start, 1'b1, CLOCK_50, rateCount);
    DisplayCounter dc0 (timeLeft, reset, start, rateCount == 1'b0, CLOCK_50);
   
    hex_decoder hd1 (.hex_digit(score[7:4]), .segments(HEX1));
    hex_decoder hd2 (.hex_digit(score[3:0]), .segments(HEX0));

    hex_decoder hd5 (.hex_digit(timeLeft[7:4]), .segments(HEX5));
    hex_decoder hd4 (.hex_digit(timeLeft[3:0]), .segments(HEX4));
endmodule


// -----------------control-----------------
module control(clk, reset, timeLeft, gridDone, farmerDone, hamsterDone, moveDone, go, start, printGrid, printFarmer, printHamster, restart, move);
    // --------------------io--------------------
    input clk;
    input reset;
    input [7:0] timeLeft;
    input gridDone, farmerDone, hamsterDone, moveDone, go, start;
    output reg printGrid, printFarmer, printHamster, restart, move;

    // -------------------------var------------------------
    reg [5:0] current_state, next_state;  

    wire timeup;
    assign timeup = (timeLeft == 8'b0);


    localparam  INIT = 6'd1,
                DRAW_GRID = 6'd2,
                DRAW_FARMER = 6'd3,
                DRAW_HAMSTER = 6'd4,
                INPUT = 6'd5,
                CHECK_INPUT = 6'd6,
                INPUT_WAIT = 6'd7,
                RESTART = 6'd8,
                MOVE = 6'd9,
                CHECK_TIME = 6'd10;

    // Next state logic aka our state table
    always@(*)
    begin: state_table
            case (current_state)
                    INIT: next_state = DRAW_GRID;
                    DRAW_GRID: next_state = gridDone ? DRAW_FARMER : DRAW_GRID;
                    DRAW_FARMER: next_state = farmerDone ? DRAW_HAMSTER : DRAW_FARMER;
                    DRAW_HAMSTER: next_state = hamsterDone ? INPUT : DRAW_HAMSTER;
                    INPUT: next_state = go ? CHECK_INPUT : INPUT;
                    CHECK_INPUT: next_state = start ? RESTART : INPUT_WAIT;
                    INPUT_WAIT: next_state = go ? INPUT_WAIT : MOVE;
                    RESTART: next_state = go ? RESTART : DRAW_GRID;
                    MOVE: next_state = moveDone ? CHECK_TIME : MOVE;
                    CHECK_TIME: next_state = timeup ? RESTART : DRAW_GRID;
            default: next_state = INIT;
        endcase
    end // state_table


    always @(*)
    begin: enable_signals
            printGrid = 1'b0;
            printFarmer = 1'b0;
            printHamster = 1'b0;
            restart = 1'b0;
            move = 1'b0;

        case (current_state)
            INIT: begin
                printGrid = 1'b0;
                printFarmer = 1'b0;
                printHamster = 1'b0;
                restart = 1'b0;
                move = 1'b0;
            end
            DRAW_GRID: begin
                printGrid = 1'b1;
                restart = 1'b0;
            end
            DRAW_FARMER: begin
                printFarmer = 1'b1;
            end
            DRAW_HAMSTER: begin
                printHamster = 1'b1;
            end
            RESTART: begin
               restart = 1'b1;
            end 
            MOVE: begin
               move = 1'b1;
           end
        endcase
    end // enable_signal

    // current_state registers
    always@(posedge clk)
    begin: state_FFs
        if(!reset)
            current_state <= INIT;
        else
            current_state <= next_state;
    end // state_FFS
endmodule


// ----------------datapath-----------------
module datapath(clk, reset, printGrid, printFarmer, printHamster, restart, move, in, grid, gridtemp, x, y, c_out, gridDone, farmerDone, hamsterDone, moveDone, farmerPos, hamsterPos, score);
    // --------------------io--------------------
    input clk;
    input reset;
    input printGrid, printFarmer, printHamster,restart, move;
    input [4:0] in;
    input [207:0] grid;
    output [7:0] x;
    output [6:0] y;
    output [2:0] c_out;
    output [7:0] score;
    output [7:0] farmerPos, hamsterPos;
    output [207:0] gridtemp;
    output gridDone, farmerDone, hamsterDone, moveDone;

    // -------------------------var------------------------
    wire [3:0] x0, y0;
    wire [2:0] x1, x2, x3, y1, y2, y3;
    wire singalDone, farmerPlaced, hamsterPlaced;
   
    wire mapbit, farmerbit, hambit;


    assign c_out = mapbit*printGrid*3'b110 + farmerbit*printFarmer*3'b100 + hambit*printHamster*3'b101 + (~mapbit*printGrid*3'b010) + (~farmerbit*printFarmer*3'b010) + (~hambit*printHamster*3'b010);
    assign x = x0*4'b1000 + x1*printGrid + x2*printFarmer + x3*printHamster + 5'd16;
    assign y = y0*4'b1000 + y1*printGrid + y2*printFarmer + y3*printHamster;

    doBlock p8(clk, printGrid, reset, x1, y1, signalDone);
    doGrid pm (clk, reset, singalDone, printFarmer, printHamster, moveDone, restart, in, start, move, grid, gridtemp, x0, y0, gridDone, farmerPlaced, hamsterPlaced, farmerPos, hamsterPos, mapbit, score);
    doFarmer ps (clk, printFarmer, farmerPlaced, reset, x2, y2, farmerbit, farmerDone);
    doHamster pmo (clk, printHamster, hamsterPlaced, reset, x3, y3, hambit, hamsterDone);

endmodule

module doGrid (clk, reset, singalDone, printFarmer, printHamster, moveDone, restart, in, start, move, grid, gridtemp, x, y, gridDone, farmerPlaced, hamsterPlaced, farmerPos, hamsterPos, WriteEn, score);
    input clk;
    input singalDone, printFarmer, printHamster,restart,move;
    input reset;
    input [207:0] grid;
    input [4:0] in;
    output reg [3:0] x;
    output reg [3:0] y;
    output reg gridDone, farmerPlaced, hamsterPlaced, moveDone, start;
    output reg WriteEn;
    output reg [7:0] score;
    output reg [7:0] farmerPos, hamsterPos;
    output reg [207:0] gridtemp;

    reg [8:0] i;
    reg [7:0] currFarmer, currHamster;


    always @ (posedge clk) begin
        if (in == 5'b10000) begin
            start <= 1'b1;
            end

        if(!reset) begin
            x <= 4'b0000;
            y <= 4'b0000;
            i <= 9'b00000000;
            score <= 8'b00000000;
            gridDone <= 1'b0;
            farmerPlaced <= 1'b0;
            hamsterPlaced <= 1'b0;
            moveDone <= 1'b0;
            WriteEn <= 1'b0;
            gridtemp <= grid;
            farmerPos <= 8'b0;
            hamsterPos <= 8'b0;
        end

        else if(singalDone) begin
            gridDone <= 1'b0;
            moveDone <= 1'b0;
            x <= i[3:0];
            y <= i[7:4];
            if (i == 9'b000000000) begin
                i <= 9'b100000000;
                gridtemp <= grid << 1'b1;
                WriteEn <= gridtemp[207];
                gridDone <= 1'b0;
            end
            else if (9'b111110000 > i && i > 9'b011111111) begin
                i <= i + 1'b1;
                gridtemp <= grid << (i[7:0] + 1'b1);
                WriteEn <= gridtemp[207];
                gridDone <= 1'b0;
            end
            else if (i == 9'b111110000) begin
                i <= 9'b000000000;
                gridDone <= 1'b1;
                WriteEn <= 1'b0;  
            end
        end

        else if (printFarmer) begin
            if (!farmerPlaced) begin
                farmerPos<=8'd104;
            end
            x <= farmerPos[3:0];
            y <= farmerPos[7:4];
            farmerPlaced <= 1'b1;
            gridDone <= 1'b0;
        end

        else if (printHamster) begin
            if (!hamsterPlaced) begin
                hamsterPos <= 8'd98;
            end
            x <= hamsterPos[3:0];
            y <= hamsterPos[7:4];
                        hamsterPlaced <= 1'b1;
            gridDone <= 1'b0;
        end

        else if(restart) begin
            farmerPlaced <= 1'b0;
            hamsterPlaced <= 1'b0;
            gridDone <= 1'b0;
        end

        else if(move) begin
            currFarmer <= farmerPos;
            currHamster <= hamsterPos;
            if(in == 5'b01000 && !moveDone) begin //left
                case (currFarmer)
                    8'd35: farmerPos <= 8'd45;
                    8'd40: farmerPos <= 8'd35;
                    8'd45: farmerPos <= 8'd40;
                    8'd99: farmerPos <= 8'd109;
                    8'd104: farmerPos <= 8'd99;
                    8'd109: farmerPos <= 8'd104;
                    8'd163: farmerPos <= 8'd173;
                    8'd168: farmerPos <= 8'd163;
                    8'd173: farmerPos <= 8'd168;
                default: farmerPos <= 8'd104;
                endcase
                moveDone <= 1'b1;
            end
            else if(in == 5'b00100 && !moveDone) begin //right
                case (currFarmer)
                    8'd35: farmerPos <= 8'd40;
                    8'd40: farmerPos <= 8'd45;
                    8'd45: farmerPos <= 8'd35;
                    8'd99: farmerPos <= 8'd104;
                    8'd104: farmerPos <= 8'd109;
                    8'd109: farmerPos <= 8'd99;
                    8'd163: farmerPos <= 8'd168;
                    8'd168: farmerPos <= 8'd173;
                    8'd173: farmerPos <= 8'd163;
                default: farmerPos <= 8'd104;
                endcase
                moveDone <= 1'b1;
            end
            else if(in == 5'b00010 && !moveDone) begin //up
                case (currFarmer)
                    8'd35: farmerPos <= 8'd163;
                    8'd40: farmerPos <= 8'd168;
                    8'd45: farmerPos <= 8'd173;
                    8'd99: farmerPos <= 8'd35;
                    8'd104: farmerPos <= 8'd40;
                    8'd109: farmerPos <= 8'd45;
                    8'd163: farmerPos <= 8'd99;
                    8'd168: farmerPos <= 8'd104;
                    8'd173: farmerPos <= 8'd109;
                default: farmerPos <= 8'd104;
                endcase
                moveDone <= 1'b1;
            end
            else if(in == 5'b00001 && !moveDone) begin //down
                case (currFarmer)
                    8'd35: farmerPos <= 8'd99;
                    8'd40: farmerPos <= 8'd104;
                    8'd45: farmerPos <= 8'd109;
                    8'd99: farmerPos <= 8'd163;
                    8'd104: farmerPos <= 8'd168;
                    8'd109: farmerPos <= 8'd173;
                    8'd163: farmerPos <= 8'd35;
                    8'd168: farmerPos <= 8'd40;
                    8'd173: farmerPos <= 8'd45;
                default: farmerPos <= 8'd104;
                endcase
                moveDone <= 1'b1;
            end

            if (hamsterPos == (farmerPos - 1'b1)) begin
                if (score == 8'b11111111) begin
                    score <= 8'b00000000;
                end
                else begin
                    score <= score + 1'b1;
                end
                case (currHamster)
                    8'd34: hamsterPos <= 8'd108;
                    8'd39: hamsterPos <= 8'd98;
                    8'd44: hamsterPos <= 8'd34;
                    8'd98: hamsterPos <= 8'd167;
                    8'd103: hamsterPos <= 8'd162;
                    8'd108: hamsterPos <= 8'd39;
                    8'd162: hamsterPos <= 8'd44;
                    8'd167: hamsterPos <= 8'd172;
                    8'd172: hamsterPos <= 8'd103;
                default: hamsterPos <= 8'd98;
                endcase
            end
        end
    end
endmodule
 
module doBlock (clk, printGrid, reset, x, y, singalDone);
    input clk;
    input printGrid;
    input reset;
    output reg [2:0] x;
    output reg [2:0] y;
    output reg singalDone;
    reg [7:0] i;

    always @ (posedge clk) begin
        if (!reset) begin
            x <= 3'b000;
            y <= 3'b000;
            i <= 8'b00000000;
            singalDone <= 1'b0;
        end

        else if (printGrid) begin
            x <= i[2:0];
            y <= i[5:3];
            singalDone <= 1'b0;
 
            if (i == 8'b00000000) begin
                i <= 8'b10000000;
            end
            else if (8'b11000000 > i && i > 8'b01111111) begin
                i <= i + 1'b1;
            end
 
            else if (i > 8'b10111111) begin
                i <= 8'b00000000;
                singalDone <= 1'b1;
            end
        end
    end
 
endmodule
 
module doFarmer (clk, printFarmer, farmerPlaced, reset, x, y, WriteEn, farmerDone);
    input clk;
    input farmerPlaced;
    input reset;
    input printFarmer;
    output reg [2:0] x;
    output reg [2:0] y;
    output reg farmerDone;
    output reg WriteEn;
    wire [63:0] farmer;
    reg [63:0] farmerTemp;
   
    assign farmer = {
    8'b11111111,
    8'b11111111,
    8'b11000000,
    8'b11111000,
    8'b11111000,
    8'b11000000,
    8'b11000000,
    8'b11000000
    };
   
    reg [7:0] i;
   
    always @ (posedge clk) begin
        if (!reset) begin
            x <= 3'b000; // Default start 80
            y <= 3'b000;
            i <= 8'b00000000;
            farmerDone <= 1'b0;
            WriteEn <= 1'b0;
        end
       
        else if (farmerPlaced && printFarmer) begin
            x <= i[2:0];
            y <= i[5:3];
            farmerDone <= 1'b0;
            WriteEn <= 1'b0;
            if (i == 8'b00000000) begin
                i <= 8'b10000000;
                farmerTemp <= farmer << 1'b1;
                WriteEn <= farmerTemp[63];
            end
            else if (8'b11000001 > i && i > 8'b01111111) begin
                i <= i + 1'b1;
                farmerTemp <= farmer << (i[5:0] + 1'b1);
                WriteEn <= farmerTemp[63];
               
            end
 
            else if (i == 8'b11000001) begin
                i <= 8'b00000000;
                farmerDone <= 1'b1;
            end
        end
    end
endmodule
 
module doHamster (clk, printHamster, hamsterPlaced, reset, x, y, WriteEn, hamsterDone);
    input clk;
    input hamsterPlaced, printHamster;
    input reset;
    output reg [2:0] x;
    output reg [2:0] y;
    output reg hamsterDone;
    output reg WriteEn;
    wire [63:0] hamster;
    reg [63:0] hamsterTemp;
   
    assign hamster = {
    8'b01111110,
    8'b10000001,
    8'b10100101,
    8'b10100101,
    8'b10000001,
    8'b10111101,
    8'b10000001,
    8'b01111110
    };
   
    reg [7:0] i;
   
    always @ (posedge clk) begin
        if (!reset) begin
            x <= 3'b000; // Default start 80
            y <= 3'b000;
            i <= 8'b00000000;
            hamsterDone <= 1'b0;
            WriteEn <= 1'b0;
        end
       
        else if (printHamster && hamsterPlaced) begin
            x <= i[2:0];
            y <= i[5:3];
            hamsterDone <= 1'b0;
            WriteEn <= 1'b0;
            if (i == 8'b00000000) begin
                i <= 8'b10000000;
                hamsterTemp <= hamster << 1'b1;
                WriteEn <= hamsterTemp[63];
            end
            else if (8'b11000000 > i && i > 8'b01111111) begin
                i <= i + 1'b1;
                hamsterTemp <= hamster << (i[5:0] + 1'b1);
                WriteEn <= hamsterTemp[63];
               
            end
 
            else if (i > 8'b10111111) begin
                i <= 8'b00000000;
                hamsterDone <= 1'b1;
            end
        end
    end
endmodule
 
module DisplayCounter (q, reset, start, Enable, clock);
    wire [7:0] d;
    assign d = 8'b01100000;
    output reg [7:0] q;
    input reset, start;
    input Enable;
    input clock;
   
    always @ (posedge clock)
    begin
            if (!reset || start)
                q <= d; //q is set to 60
            else if (Enable) begin
                if (q == 8'b00000000) begin
                    q <= 8'b00000000;
                end
                else if (q[3:0] > 4'b1001) begin
                    q[3:0] <= 4'b1001;
                end
                else if (q[3:0] == 4'b0000) begin
                    q <= q - 1'b1;
                    q[3:0] <= 4'b1001;
                end
                else if (q[3:0] < 4'b1010) begin
                    q <= q - 1'b1;
                end
            end
    end
endmodule

module RateDivider (d, reset, start, Enable, clock, q);
    output reg [27:0] q;
    input wire [27:0] d;
    input reset, start;
    input Enable;
    input clock;
   
    always @ (posedge clock)
    begin
            if (!reset || start) 
                q <= 28'h2faf080; //q is set to 0
            else if (q == 28'b0) 
                q <= d; //q reset to default
            else if (Enable)
                q <= q - 1;
    end
endmodule
 
module hex_decoder(hex_digit, segments);
    input [3:0] hex_digit;
    output reg [6:0] segments;
   
    always @(*)
        case (hex_digit)
            4'h0: segments = 7'b100_0000;
            4'h1: segments = 7'b111_1001;
            4'h2: segments = 7'b010_0100;
            4'h3: segments = 7'b011_0000;
            4'h4: segments = 7'b001_1001;
            4'h5: segments = 7'b001_0010;
            4'h6: segments = 7'b000_0010;
            4'h7: segments = 7'b111_1000;
            4'h8: segments = 7'b000_0000;
            4'h9: segments = 7'b001_1000;
            4'hA: segments = 7'b000_1000;
            4'hB: segments = 7'b000_0011;
            4'hC: segments = 7'b100_0110;
            4'hD: segments = 7'b010_0001;
            4'hE: segments = 7'b000_0110;
            4'hF: segments = 7'b000_1110;
            default: segments = 7'h7f;
        endcase
endmodule
