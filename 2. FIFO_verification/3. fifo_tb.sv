`timescale 1ns / 1ps

class transaction;
    rand bit oper; // randomization bit for operation control (1/0)
    bit rd,wr; // read and write control bits
    bit full,empty; // flags for full and empty status
  bit [7:0] data_in; // 8 bit data input
  bit [7:0] data_out; // 8 bit data output

    constraint oper_ctrl{
    oper dist {0 :/ 50, 1 :/50}; // range 0=50% and 1=50%
        }

endclass

class generator;
    transaction tr; // creating transaction object to generate and send
    mailbox #(transaction) mbx; // mailbox for communication
    int count=0; // no of transaction to generate
    int i=0; // no of iteration counter

    event next; // event to signal when to send the next transaction
    event done; // event to convey completion of transaction

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        tr = new();
    endfunction

    task run();
        repeat(count) begin
            assert(tr.randomize) else $error("Randomization Failed");
            i++;
            mbx.put(tr);
            $display("[GEN] : oper: %0d iteration : %0d",tr.oper,i);
            @(next);
        end
        -> done;
    endtask

endclass

class driver;
    transaction datac;
    mailbox #(transaction) mbx;
    virtual fifo_if.drv_mp fif;

        function new(mailbox #(transaction) mbx);
            this.mbx = mbx;
        endfunction

        task reset();
            fif.rst <= 1'b1;
            fif.rd <= 1'b0;
            fif.wr <= 1'b0;
            fif.data_in <= 8'd0;

          repeat(5) @(posedge fif.clock) ;

            fif.rst <= 1'b0;
            $display("[DRV]: reset done");
          $display("-------------------------------");
          
        endtask

        task write();
          @(posedge fif.clock) ;
            fif.rst <= 1'b0;
            fif.rd <= 1'b0;
            fif.wr <= 1'b1;
          fif.data_in <= $urandom_range(1,5);
          @(posedge fif.clock);
            fif.wr <= 1'b0;
          $display("[DRV] : datain:%0d",fif.data_in); 
          @(posedge fif.clock);
        endtask

        task read();
          @(posedge fif.clock);
            fif.rd <= 1'b1;
            fif.rst <= 1'b0;
            fif.wr <= 1'b0;
          @(posedge fif.clock);
            fif.rd <= 1'b0;
            $display("[DRV]: data read");
          @(posedge fif.clock);
        endtask

        task run();
            forever begin
                mbx.get(datac);
                if(datac.oper == 1'b1)
                    write();
                else
                    read();
            end
        endtask
endclass

class monitor;
    virtual fifo_if.mon_mp fif;
    transaction tr;
    mailbox #(transaction) mbx;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction
    
    task run();
        tr = new();
        forever begin
          repeat(2) @(posedge fif.clock);

            tr.wr = fif.wr;
            tr.rd = fif.rd;
            tr.data_in = fif.data_in;
            tr.full = fif.full;
            tr.empty = fif.empty;

          @(posedge fif.clock);
            tr.data_out = fif.data_out;
          
            mbx.put(tr);

          $display("[MON]: wr:%0d,rd:%0d,din:%0d,dout:%0d,full:%0d,empty:%0d",tr.wr,tr.rd,tr.data_in,tr.data_out,tr.full,tr.empty);
        end
    endtask
endclass

class scoreboard;
    mailbox #(transaction) mbx;
    transaction tr;
    event next;
    bit[7:0] din[$] ; // array to store written data
    bit[7:0] temp; // temporary data storage
    int err=0; // error count

    function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    endfunction

    task run();
        forever begin
            mbx.get(tr);
          $display("[SCO]: wr:%0d,rd:%0d,din:%0d,dout:%0d,full:%0d,empty:%0d",tr.wr,tr.rd,tr.data_in,tr.data_out,tr.full,tr.empty);
            
            if(tr.wr == 1'b1) begin
                if(tr.full == 1'b0) begin
                  din.push_front(tr.data_in);
                  $display("[SCO]: data stored in queue: %0d",tr.data_in);
                end
                else begin
                    $display("[SCO]: Fifo is full");
            end
        end

        if(tr.rd == 1'b1) begin
            if(tr.empty == 1'b0) begin
                temp = din.pop_back();

              if(tr.data_out == temp)
                    $display("[SCO]: data matched");
                else begin
                    $error("[SCO]: data mismatched");
                    err++;
                end
            end
            else begin
                $display("[SCO]: fifo is empty");
            end
            end
          ->next;
        end
            
    endtask
endclass

class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    mailbox #(transaction) gdmbx;
    mailbox #(transaction) msmbx;

    event nextgs;
    virtual fifo_if fif;

        function new(virtual fifo_if fif);
            gdmbx = new();
            gen = new(gdmbx);
            drv = new(gdmbx);
            msmbx = new();
            mon = new(msmbx);
            sco = new(msmbx);

            this.fif = fif;
            drv.fif = this.fif;
            mon.fif = this.fif;

            gen.next = nextgs;
            sco.next = nextgs;

        endfunction

        task pre_test();
            drv.reset();
        endtask

        task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any

        endtask

        task post_test();
            wait(gen.done.triggered);
          $display("---------------------------------------------");
    
            $display("error count:%0d",sco.err);
          $display("---------------------------------------------");
    
            $finish();
        endtask

        task run();
            pre_test();
            test();
            post_test();

        endtask
endclass


module fifo_tb;
    fifo_if fif();
  fifo dut(.rd(fif.rd),.wr(fif.wr),.full(fif.full),.empty(fif.empty),.din(fif.data_in),.dout(fif.data_out),.clk(fif.clock),.rst(fif.rst));
   
    initial begin
        fif.clock <= 0;
    end

    always #10 fif.clock <= ~fif.clock;

    environment env;

    initial begin
        env = new(fif);
        env.gen.count = 10;
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule
