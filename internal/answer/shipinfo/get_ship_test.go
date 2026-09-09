package shipinfo

import (
	"testing"

	"github.com/ggmolly/belfast/internal/connection"
	"github.com/ggmolly/belfast/internal/packets"
	"github.com/ggmolly/belfast/internal/protobuf"
	"google.golang.org/protobuf/proto"
)

func TestGetShipWithoutCommanderReturnsProtocolFailure(t *testing.T) {
	request := &protobuf.CS_12025{
		Type:    proto.Uint32(1),
		PosList: []uint32{1},
	}
	buffer, err := proto.Marshal(request)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	client := &connection.Client{}
	_, packetID, err := GetShip(&buffer, client)
	if err != nil {
		t.Fatalf("get ship returned error: %v", err)
	}
	if packetID != 12026 {
		t.Fatalf("expected response packet 12026, got %d", packetID)
	}

	responseBytes := client.Buffer.Bytes()
	if len(responseBytes) < packets.HEADER_SIZE {
		t.Fatalf("expected framed response, got %d bytes", len(responseBytes))
	}
	response := &protobuf.SC_12026{}
	if err := proto.Unmarshal(responseBytes[packets.HEADER_SIZE:], response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if response.GetResult() != 1 {
		t.Fatalf("expected invalid-state result 1, got %d", response.GetResult())
	}
}
