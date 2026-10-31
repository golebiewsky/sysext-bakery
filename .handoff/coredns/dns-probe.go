package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"os"
	"time"
)

func probe(protocol, address, expected string) error {
	conn, err := net.DialTimeout(protocol, address, 3*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	packet := []byte{0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}
	packet = append(packet, 6, 's', 'y', 's', 'e', 'x', 't', 4, 't', 'e', 's', 't', 0, 0, 1, 0, 1)
	outgoing := packet
	if protocol == "tcp" {
		outgoing = append([]byte{byte(len(packet) >> 8), byte(len(packet))}, packet...)
	}
	if _, err = conn.Write(outgoing); err != nil {
		return err
	}
	reply := make([]byte, 4096)
	if protocol == "tcp" {
		header := make([]byte, 2)
		if _, err = io.ReadFull(conn, header); err != nil {
			return err
		}
		size := int(binary.BigEndian.Uint16(header))
		reply = make([]byte, size)
		if _, err = io.ReadFull(conn, reply); err != nil {
			return err
		}
	} else {
		size, err := conn.Read(reply)
		if err != nil {
			return err
		}
		reply = reply[:size]
	}
	if len(reply) < 16 || binary.BigEndian.Uint16(reply[:2]) != 0x1234 || reply[3]&15 != 0 || binary.BigEndian.Uint16(reply[6:8]) != 1 {
		return fmt.Errorf("unexpected DNS response: %x", reply)
	}
	actual := net.IP(reply[len(reply)-4:]).String()
	if actual != expected {
		return fmt.Errorf("got %s, want %s", actual, expected)
	}
	fmt.Printf("PASS: %s %s sysext.test = %s\n", protocol, address, actual)
	return nil
}

func main() {
	address, expected := "127.0.0.1:53", "192.0.2.10"
	if len(os.Args) > 1 {
		address = os.Args[1]
	}
	if len(os.Args) > 2 {
		expected = os.Args[2]
	}
	for _, protocol := range []string{"udp", "tcp"} {
		if err := probe(protocol, address, expected); err != nil {
			fmt.Fprintln(os.Stderr, protocol, err)
			os.Exit(1)
		}
	}
}
