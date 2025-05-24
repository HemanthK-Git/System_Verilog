`timescale 1ns / 1ps

// 1. Transaction class: Represents one input-output data set for D flip-flop
class transaction;
    randc bit din;       // Random input bit 'din' (random cyclic to cover all values)
    bit dout;            // Output bit 'dout' captured from DUT

    // Copy function: returns a new transaction object copying current values
    function transaction copy();
        copy = new(); // create new transaction object
        copy.din =this.din;      // copy input value
        copy.dout = this.dout;    // copy output value
        return copy;              // return the copied object
    endfunction

    // Display function: prints transaction data with a tag for identification
    function void display(input string tag);
        $display("[%0s]: Din=%0b Dout=%0b", tag, din, dout);
    endfunction
endclass


// 2. Generator class: Creates and sends random stimulus transactions
class generator;
    transaction tr;                  // Transaction object to hold stimulus
    mailbox #(transaction) mbx;      // Mailbox to send transactions to driver
    mailbox #(transaction) mbxref;   // Mailbox to send reference transactions to scoreboard
    event done;                     // Event triggered after all stimulus are sent
    event sconext;                  // Event to synchronize with scoreboard completion
    int count;                      // Number of transactions to generate

    // Constructor: takes mailboxes to communicate with driver and scoreboard
    function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
        tr = new();
    endfunction 

    // Run task: generates 'count' transactions and sends copies to driver & scoreboard
    task run();
        repeat (count) begin
            // Randomize din, check success
            assert(tr.randomize()) else $error("[GEN] : Randomize failed");

            // Put copies of transaction into driver and scoreboard mailboxes
            mbx.put(tr.copy());
            mbxref.put(tr.copy());

            // Display generated transaction
            tr.display("GEN");

            // Wait for scoreboard to signal completion before next stimulus
            @(sconext);
        end
        -> done; // Trigger 'done' event to signal stimulus completion
    endtask
endclass


// 3. Driver class: Receives transactions from generator and applies inputs to DUT
class driver;
    transaction tr;                // Transaction received from generator
    mailbox #(transaction) mbx;    // Mailbox to receive transactions from generator
    virtual d_ff_if vif;           // Virtual interface connection to DUT signals

    // Constructor: initializes mailbox
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    // Reset task: applies reset signal to DUT for 5 clock cycles
    task reset();
        vif.rst <= 1'b1;           // Assert reset
        repeat (5) @(posedge vif.clk);  // Hold reset for 5 clock cycles
        vif.rst <= 1'b0;           // Deassert reset
        @(posedge vif.clk);        // Wait one more clock cycle
        $display("[DRV]: Reset Done");
    endtask

    // Run task: waits for transactions, applies input din to DUT
    task run();
        tr = new();
        forever begin
            mbx.get(tr);           // Get next transaction from generator
            vif.din <= tr.din;     // Apply input din to DUT
            @(posedge vif.clk);    // Wait for one clock cycle
            tr.display("DRV");     // Display driver applied transaction
            vif.din <= 1'b0;       // Clear input after applying
            @(posedge vif.clk);    // Wait for one clock cycle before next
        end
    endtask
endclass


// 4. Monitor class: Observes DUT output and sends to scoreboard
class monitor;
    transaction tr;                // Transaction object to capture DUT output
    mailbox #(transaction) mbx;    // Mailbox to send transactions to scoreboard
    virtual d_ff_if vif;           // Virtual interface to DUT signals

    // Constructor: initialize mailbox
    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    // Run task: continuously samples output dout after two clocks and sends to scoreboard
    task run();
        tr = new();
        forever begin
            repeat (2) @(posedge vif.clk);   // Wait 2 clock cycles to let DUT output stabilize
            tr.dout = vif.dout;               // Capture output from DUT
            mbx.put(tr);                     // Send output transaction to scoreboard
            tr.display("MON");               // Display monitor captured transaction
        end
    endtask
endclass


// 5. Scoreboard class: Compares DUT output from monitor against reference from generator
class scoreboard;
    transaction tr;                 // Transaction from monitor
    transaction trref;              // Reference transaction from generator
    mailbox #(transaction) mbx;     // Mailbox to receive monitor transactions
    mailbox #(transaction) mbxref;  // Mailbox to receive reference transactions
    event sconext;                 // Event to signal generator that scoreboard completed comparison

    // Constructor: initialize mailboxes
    function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
    endfunction

    // Run task: waits for transaction pairs, compares, displays results, signals generator
    task run();
        forever begin
            mbx.get(tr);        // Get transaction from monitor
            mbxref.get(trref);  // Get corresponding reference transaction

            tr.display("SCO");  // Display monitored transaction
            trref.display("REF"); // Display reference transaction

            // Check if DUT output matches expected input
            if (tr.dout == trref.din)
                $display("[SCO]: Output Matched");
            else
                $display("[SCO]: Output Mismatched");

            -> sconext;  // Signal generator that comparison is done, generator can send next stimulus
        end
    endtask
endclass


// 6. Environment class: Creates and connects all components and manages simulation flow
class environment;
    generator gen; // generator instance
    driver drv; // driver instance
    monitor mon; // monitor instance
    scoreboard sco; // scoreboard instance

    mailbox #(transaction) gdmbx;    // Generator to Driver mailbox
    mailbox #(transaction) msmbx;    // Monitor to Scoreboard mailbox
    mailbox #(transaction) mbxref;   // Generator to Scoreboard mailbox

    event next;                     // Synchronization event between generator and scoreboard

    virtual d_ff_if vif;            // Virtual interface connected to DUT

    // Constructor: creates components and connects mailboxes and interface
    function new(virtual d_ff_if vif);
        
        // store the dut interface
        this.vif = vif;
        
        // create mailbox
        gdmbx = new();
        msmbx = new();
        mbxref = new();

        // create components
        gen = new(gdmbx, mbxref);
        drv = new(gdmbx);
        mon = new(msmbx);
        sco = new(msmbx, mbxref);

        // Connect virtual interface to driver and monitor
        drv.vif = this.vif;
        mon.vif = this.vif;

        // Synchronize generator and scoreboard with event
        gen.sconext = next;
        sco.sconext = next;
    endfunction

    // Pre-test setup: reset DUT
    task pre_test();
        drv.reset();
    endtask

    // Run all components concurrently
    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
    endtask

    // Post-test: wait for generation to finish and end simulation
    task post_test();
        wait(gen.done.triggered);
        $finish;
    endtask

    // Run full environment sequence
    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass


// 7. Testbench module: Instantiates DUT, interface, environment and starts simulation
module d_ff_tb;
    environment env;         // Environment instance
    d_ff_if vif();           // Interface instance
    d_ff dut(vif);          // DUT instance connected with interface

    initial begin
        vif.clk <= 1'b0;    // Initialize clock to zero
    end

    // Clock generation: toggles every 10 time units => 50MHz clock
    always #10 vif.clk <= ~vif.clk;

    initial begin
        env = new(vif);     // Create environment with virtual interface
        env.gen.count = 30; // Number of transactions to generate
        env.run();          // Start environment run sequence
    end
    
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
  
endmodule
