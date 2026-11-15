package httpapi

import "testing"

func TestPushTokenRequestResolvesFirebaseTargets(t *testing.T) {
	tests := []struct {
		name     string
		request  pushTokenRequest
		wantID   string
		wantType string
		wantErr  bool
	}{
		{
			name:     "explicit installation ID",
			request:  pushTokenRequest{InstallationID: "Abcdefghijklmnopqrstuv", TargetType: "fid"},
			wantID:   "Abcdefghijklmnopqrstuv",
			wantType: "fid",
		},
		{
			name:     "legacy app placed the FID in token field",
			request:  pushTokenRequest{Token: "Abcdefghijklmnopqrstuv"},
			wantID:   "Abcdefghijklmnopqrstuv",
			wantType: "fid",
		},
		{
			name:     "legacy FCM registration token",
			request:  pushTokenRequest{Token: "legacy-fcm-registration-token"},
			wantID:   "legacy-fcm-registration-token",
			wantType: "token",
		},
		{
			name:    "ambiguous target fields",
			request: pushTokenRequest{Token: "Abcdefghijklmnopqrstuv", InstallationID: "Abcdefghijklmnopqrstuv"},
			wantErr: true,
		},
		{
			name:    "unsupported target type",
			request: pushTokenRequest{Token: "legacy-token", TargetType: "topic"},
			wantErr: true,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			gotID, gotType, err := test.request.resolveTarget()
			if test.wantErr {
				if err == nil {
					t.Fatal("expected target validation error")
				}
				return
			}
			if err != nil {
				t.Fatalf("resolve target: %v", err)
			}
			if gotID != test.wantID || gotType != test.wantType {
				t.Fatalf("target = (%q, %q), want (%q, %q)", gotID, gotType, test.wantID, test.wantType)
			}
		})
	}
}
