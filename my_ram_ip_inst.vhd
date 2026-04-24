my_ram_ip_inst : my_ram_ip PORT MAP (
		clock	 => clock_sig,
		data	 => data_sig,
		rdaddress	 => rdaddress_sig,
		wraddress	 => wraddress_sig,
		wren	 => wren_sig,
		q	 => q_sig
	);
