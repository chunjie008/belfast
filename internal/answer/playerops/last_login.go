package playerops

import (
	"fmt"
	"time"

	"github.com/ggmolly/belfast/internal/connection"
	"github.com/ggmolly/belfast/internal/logger"
	"github.com/ggmolly/belfast/internal/orm"

	"github.com/ggmolly/belfast/internal/protobuf"
	"google.golang.org/protobuf/proto"
)

// Reimplementation of SC_11000
func LastLogin(buffer *[]byte, client *connection.Client) (int, int, error) {
	if client == nil {
		return 0, 11000, fmt.Errorf("last login: nil client")
	}
	if client.Commander == nil {
		if client.AuthArg2 == 0 {
			return 0, 11000, fmt.Errorf("last login: commander is not bound to session")
		}
		mapping, err := orm.GetYostarusMapByArg2(client.AuthArg2)
		if err != nil {
			return 0, 11000, fmt.Errorf("last login: resolve account for arg2 %d: %w", client.AuthArg2, err)
		}
		if mapping.AccountID == 0 {
			return 0, 11000, fmt.Errorf("last login: account for arg2 %d is not created", client.AuthArg2)
		}
		if err := client.GetCommander(mapping.AccountID); err != nil {
			return 0, 11000, fmt.Errorf("last login: load account %d: %w", mapping.AccountID, err)
		}
		if err := client.Commander.Load(); err != nil {
			return 0, 11000, fmt.Errorf("last login: load commander %d: %w", mapping.AccountID, err)
		}
	}
	now := time.Now().UTC()
	nowUnix := uint32(now.Unix())
	if _, err := orm.ApplyCommanderMoraleRecovery(client.Commander.CommanderID, nowUnix); err != nil {
		return 0, 11000, err
	}
	sc11000 := protobuf.SC_11000{
		Timestamp:               proto.Uint32(nowUnix),
		Monday_0OclockTimestamp: proto.Uint32(1606114800), // 23/11/2020 08:00:00
	}
	client.PreviousLoginAt = client.Commander.LastLogin
	if err := applyNavalAcademyLoginCatchup(client, now); err != nil {
		return 0, 11000, err
	}
	if err := client.Commander.Load(); err != nil {
		return 0, 11000, err
	}
	client.Commander.BumpLastLogin()
	logger.LogEvent("Server", "SC_11000", "Updated last login of uid="+fmt.Sprint(client.Commander.CommanderID), logger.LOG_LEVEL_INFO)
	return client.SendMessage(11000, &sc11000)
}
