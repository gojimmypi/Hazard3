#include "tb_cli.h"
#include "tb_jtag.h"

#include <stdio.h>
#include <iostream>

// This file contains socket management logic and parsing of OpenOCD bitbang
// packets.


static int wait_for_connection(int server_fd, uint16_t port, struct sockaddr *sock_addr, socklen_t *sock_addr_len) {
	int sock_fd;
	printf("Waiting for connection on port %u\n", port);
	if (listen(server_fd, 3) < 0) {
		fprintf(stderr, "listen failed\n");
		exit(-1);
	}
	sock_fd = accept(server_fd, sock_addr, sock_addr_len);
	if (sock_fd < 0) {
		fprintf(stderr, "accept failed\n");
		exit(-1);
	}
	printf("Connected\n");
	return sock_fd;
}

tb_jtag_state::tb_jtag_state(const tb_cli_args &_args) {
	args = _args;
	sock_opt = 1;
	sock_addr_len = sizeof(sock_addr);
	rx_ptr = 0;
	rx_remaining = 0;
	tx_ptr = 0;

	if (args.port != 0) {
		server_fd = socket(AF_INET, SOCK_STREAM, 0);
		if (server_fd == 0) {
			fprintf(stderr, "socket creation failed\n");
			exit(-1);
		}

		int setsockopt_rc = setsockopt(
			server_fd, SOL_SOCKET, SO_REUSEADDR,
			&sock_opt, sizeof(sock_opt)
		);
		if (!setsockopt_rc) {
			setsockopt_rc = setsockopt(
				server_fd, SOL_SOCKET, SO_REUSEPORT,
				&sock_opt, sizeof(sock_opt)
			);
		}

		if (setsockopt_rc) {
			fprintf(stderr, "setsockopt failed: %d\n", setsockopt_rc);
			exit(-1);
		}

		sock_addr.sin_family = AF_INET;
		sock_addr.sin_addr.s_addr = INADDR_ANY;
		sock_addr.sin_port = htons(args.port);
		if (bind(server_fd, (struct sockaddr *)&sock_addr, sizeof(sock_addr)) < 0) {
			fprintf(stderr, "bind failed\n");
			exit(-1);
		}

		sock_fd = wait_for_connection(server_fd, args.port, (struct sockaddr *)&sock_addr, &sock_addr_len);
	}

	if (args.dump_jtag) {
		jtag_dump_fd.open(args.jtag_dump_path);
		if (!jtag_dump_fd.is_open()) {
			std::cerr << "Failed to open \"" << args.jtag_dump_path << "\"\n";
			exit(-1);
		}
	}

	if (args.replay_jtag) {
		jtag_replay_fd.open(args.jtag_replay_path);
		if (!jtag_replay_fd.is_open()) {
			std::cerr << "Failed to open \"" << args.jtag_replay_path << "\"\n";
			exit(-1);
		}
	}

}

// Return true if an exit command was received
bool tb_jtag_state::step(tb_top &tb) {
	if (args.port == 0 && !args.replay_jtag) {
		return false;
	}
	// If JTAG is enabled, we run the simulator in lockstep with the remote
	// bitbang commands, to get more consistent simulation traces. This slows
	// down simulation quite a bit compared with normal free-running.
	//
	// Most bitbang commands complete in one cycle (e.g. TCK/TMS/TDI writes)
	// but reads take 0 cycles, step=false.
	bool got_exit_cmd = false;
	bool step = false;
	while (!step) {
		if (rx_remaining > 0) {
			char c = rxbuf[rx_ptr++];
			--rx_remaining;

			if (c == 'r' || c == 's') {
				tb.set_trst_n(true);
				step = true;
			} else if (c == 't' || c == 'u') {
				tb.set_trst_n(false);
			} else if (c >= '0' && c <= '7') {
				int mask = c - '0';
				tb.set_tck(mask & 0x4);
				tb.set_tms(mask & 0x2);
				tb.set_tdi(mask & 0x1);
				step = true;
			} else if (c == 'R') {
				txbuf[tx_ptr++] = tb.get_tdo() ? '1' : '0';
				if (tx_ptr >= TCP_BUF_SIZE || rx_remaining == 0) {
					send(sock_fd, txbuf, tx_ptr, 0);
					tx_ptr = 0;
				}
			} else if (c == 'Q') {
				printf("OpenOCD sent quit command\n");
				got_exit_cmd = true;
				step = true;
			}
		} else {
			// Potentially the last command was not a read command, but
			// OpenOCD is still waiting for a last response from its
			// last command packet before it sends us any more, so now is
			// the time to flush TX.
			if (tx_ptr > 0) {
				send(sock_fd, txbuf, tx_ptr, 0);
				tx_ptr = 0;
			}
			rx_ptr = 0;
			if (args.replay_jtag) {
				rx_remaining = jtag_replay_fd.readsome(rxbuf, TCP_BUF_SIZE);
			} else {
				rx_remaining = read(sock_fd, &rxbuf, TCP_BUF_SIZE);
			}
			if (args.dump_jtag && rx_remaining > 0) {
				jtag_dump_fd.write(rxbuf, rx_remaining);
			}
			if (rx_remaining == 0) {
				if (args.port == 0) {
					// Presumably EOF, so quit.
					got_exit_cmd = true;
				} else {
					// The socket is closed. Wait for another connection.
					sock_fd = wait_for_connection(server_fd, args.port, (struct sockaddr *)&sock_addr, &sock_addr_len);
				}
			}
		}
	}
	return got_exit_cmd;
}

void tb_jtag_state::close() {
	::close(sock_fd);
	if (args.dump_jtag) {
		jtag_dump_fd.close();
	}
	if (args.replay_jtag) {
		jtag_replay_fd.close();
	}
}
