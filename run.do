vlib work
vdel -all
.main clear

transcript file run_file.log

vlib work
vlog usb_tb.sv +acc
vsim usb_tb  -l run.log
#add wave -position insertpoint "sim:/usb_packet_generator_tb/uut/*"
#add wave -position insertpoint "sim:/usb_packet_generator_tb/*"

#add wave -position insertpoint "sim:/usb_packet_generator_tb_1/dut/*"
#add wave -position insertpoint "sim:/usb_packet_generator_tb_1/*"

#add wave -position insertpoint "sim:/usb_packet_generator_tb_2/dut/*"
#add wave -position insertpoint "sim:/usb_packet_generator_tb_2/*"
add wave -position insertpoint "sim:/usb_tb/dut/*"

