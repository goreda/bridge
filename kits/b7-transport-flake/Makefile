CC ?= gcc
CFLAGS ?= -std=gnu11 -O2 -Wall -Wextra -Werror -I src
SRC = src/rt_transport.c src/rt_wire_posix.c

all: tests/test_engine tests/e2e_client tests/test_wire

tests/test_engine: tests/test_engine.c src/rt_transport.c src/rt_transport.h
	$(CC) $(CFLAGS) -o $@ tests/test_engine.c src/rt_transport.c

tests/e2e_client: tests/e2e_client.c $(SRC) src/rt_transport.h src/rt_wire_posix.h
	$(CC) $(CFLAGS) -o $@ tests/e2e_client.c $(SRC)

tests/test_wire: tests/test_wire.c $(SRC) src/rt_transport.h src/rt_wire_posix.h
	$(CC) $(CFLAGS) -o $@ tests/test_wire.c $(SRC)

check: all
	./tests/test_engine
	sh tests/run_e2e.sh

check-san:
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -o tests/test_engine_san tests/test_engine.c src/rt_transport.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -o tests/e2e_client_san tests/e2e_client.c $(SRC)
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -o tests/test_wire_san tests/test_wire.c $(SRC)
	./tests/test_engine_san
	RT_SAN=1 sh tests/run_e2e.sh

clean:
	rm -f tests/test_engine tests/e2e_client tests/test_wire tests/*_san
.PHONY: all check check-san clean
