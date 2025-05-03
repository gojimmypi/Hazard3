#pragma once

#include "tb_cli.h"

#include <cstdint>
#include <string>

#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

#ifdef __x86_64__
#define I64_FMT "%ld"
#else
#define I64_FMT "%lld"
#endif

#define MEM_SIZE (16 * 1024 * 1024)
#define N_RESERVATIONS (2)
#define RESERVATION_ADDR_MASK (0xfffffff8u)

static const unsigned int IO_BASE = 0x80000000;
enum {
	IO_PRINT_CHAR  = 0x000,
	IO_PRINT_U32   = 0x004,
	IO_EXIT        = 0x008,
	IO_SET_SOFTIRQ = 0x010,
	IO_CLR_SOFTIRQ = 0x014,
	IO_GLOBMON_EN  = 0x018,
	IO_POISON_ADDR = 0x01c,
	IO_SET_IRQ     = 0x020,
	IO_CLR_IRQ     = 0x030,
	IO_MTIME       = 0x100,
	IO_MTIMEH      = 0x104,
	IO_MTIMECMP0   = 0x108,
	IO_MTIMECMP0H  = 0x10c,
	IO_MTIMECMP1   = 0x110,
	IO_MTIMECMP1H  = 0x114
};

struct mem_io_state;
class tb_top;

typedef enum {
	SIZE_BYTE = 0,
	SIZE_HWORD = 1,
	SIZE_WORD = 2
} bus_size_t;

struct bus_request {
	uint32_t addr;
	bus_size_t size;
	bool write;
	bool excl;
	uint32_t wdata;
	int reservation_id;
	bus_request(): addr(0), size(SIZE_BYTE), write(0), excl(0), wdata(0), reservation_id(0) {}
};

struct bus_response {
	uint32_t rdata;
	int stall_cycles;
	bool err;
	bool exokay;
	bus_response(): rdata(0), stall_cycles(0), err(false), exokay(true) {}
};

typedef bus_response (*mem_access_callback_t)(tb_top &tb, mem_io_state &memio, bus_request req);

// Default callback:
bus_response tb_mem_access(tb_top &tb, mem_io_state &memio, bus_request req);

// Abstract test harness class. Concrete implementations of this class contain
// the actual C++ cycle model as well as the glue for this interface.
class tb_top {
protected:
	mem_access_callback_t mem_callback_i;
	mem_access_callback_t mem_callback_d;
	uint64_t rand_state[4];
public:
	void set_mem_callback_i(mem_access_callback_t cb) {mem_callback_i = cb;}
	void set_mem_callback_d(mem_access_callback_t cb) {mem_callback_d = cb;}

	tb_top(const tb_cli_args &args) {
		mem_callback_i = tb_mem_access;
		mem_callback_d = tb_mem_access;
		seed_rand((const uint8_t*)"looks random to me", 18);
	}

	void seed_rand(const uint8_t *data, size_t len);
	uint32_t rand();

	virtual void step(const tb_cli_args &args, mem_io_state &memio) = 0;

	virtual void set_trst_n(bool trst_n) = 0;
	virtual void set_tck(bool tck) = 0;
	virtual void set_tdi(bool tdi) = 0;
	virtual void set_tms(bool tms) = 0;
	virtual bool get_tdo() = 0;

	virtual void set_irq(uint32_t mask) = 0;
	virtual void set_soft_irq(uint8_t mask) = 0;
	virtual void set_timer_irq(uint8_t mask) = 0;
};

struct mem_io_state {
	uint64_t mtime;
	uint64_t mtimecmp[2];

	bool exit_req;
	uint32_t exit_code;

	uint8_t *mem;

	bool monitor_enabled;
	bool reservation_valid[2];
	uint32_t reservation_addr[2];
	uint32_t poison_addr;

	uint8_t soft_irq_state;
	uint32_t irq_state;

	mem_io_state(const tb_cli_args &args);

	~mem_io_state() {
		delete mem;
	}

	void step(tb_top &tb);
};
