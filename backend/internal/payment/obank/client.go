package obank

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
)

const maxResponseBytes = 64 * 1024

var client = &http.Client{
	Timeout: 12 * time.Second,
	CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	},
}

type Invoice struct {
	ID         string
	PaymentURL string
	AppLink    string
}

type CreateInvoiceData struct {
	OrderID       string  `json:"order_id"`
	Description   string  `json:"desc"`
	Amount        int64   `json:"amount"`
	Currency      string  `json:"currency"`
	Test          int     `json:"test"`
	LongTerm      int     `json:"long_term"`
	UserTo        *string `json:"user_to"`
	DateLife      *string `json:"date_life"`
	DateStartPush *string `json:"date_start_push"`
	CountPush     *int    `json:"count_push"`
	SendPush      int     `json:"send_push"`
	SendSMS       int     `json:"send_sms"`
	SuccessURL    string  `json:"success_url"`
	FailURL       string  `json:"fail_url"`
	FieldsOther   *string `json:"fields_other"`
	TransType     *string `json:"transtype"`
	ResultURL     string  `json:"result_url"`
}

type statusPaymentData struct {
	InvoiceID string `json:"invoice_id"`
	OrderID   string `json:"order_id"`
	Mark      *int   `json:"mark"`
}

type apiRequest struct {
	Cmd     string `json:"cmd"`
	Version int    `json:"version"`
	SID     string `json:"sid"`
	Mktime  string `json:"mktime"`
	Lang    string `json:"lang"`
	Data    any    `json:"data"`
}

type signedAPIRequest struct {
	Cmd     string `json:"cmd"`
	Version int    `json:"version"`
	SID     string `json:"sid"`
	Mktime  string `json:"mktime"`
	Lang    string `json:"lang"`
	Data    any    `json:"data"`
	Hash    string `json:"hash"`
}

type apiEnvelope struct {
	Data json.RawMessage `json:"data"`
}

type invoiceResponseData struct {
	InvoiceID  json.RawMessage `json:"invoice_id"`
	PaylinkURL string          `json:"paylink_url"`
	SitePay    string          `json:"site_pay"`
	AppLink    string          `json:"link_app"`
}

type statusResponseData struct {
	Status   string                  `json:"status"`
	Payments []statusPaymentResponse `json:"payments"`
}

type statusPaymentResponse struct {
	TransactionID string `json:"trans_id"`
	Amount        string `json:"amount"`
	Status        string `json:"status"`
	OrderID       string `json:"order_id"`
	Test          string `json:"test"`
}

type PaymentStatus struct {
	Status        string
	TransactionID string
	AmountKopecks int64
}

type rawResult struct {
	TransID  json.RawMessage `json:"trans_id"`
	Status   json.RawMessage `json:"status_pay"`
	SiteID   json.RawMessage `json:"site_id"`
	OrderID  json.RawMessage `json:"order_id"`
	Amount   json.RawMessage `json:"amount"`
	Currency json.RawMessage `json:"currency"`
	Mktime   json.RawMessage `json:"mktime"`
	Test     json.RawMessage `json:"test"`
	Invoice  json.RawMessage `json:"invoice_id"`
	Hash     json.RawMessage `json:"hash"`
}

type Result struct {
	TransactionID string
	Status        int
	SiteID        string
	OrderID       string
	AmountKopecks int64
	Currency      string
	Test          int
	InvoiceID     string
}

func CreateInvoice(ctx context.Context, cfg config.OBankConfig, data CreateInvoiceData) (Invoice, error) {
	var response apiEnvelope
	if err := call(ctx, cfg, "createInvoice", data, &response); err != nil {
		return Invoice{}, err
	}
	var invoiceData invoiceResponseData
	if err := json.Unmarshal(response.Data, &invoiceData); err != nil {
		return Invoice{}, errors.New("O!Dengi returned an invalid invoice response")
	}
	id, ok := scalar(invoiceData.InvoiceID)
	if !ok || id == "" {
		return Invoice{}, errors.New("O!Dengi did not return an invoice ID and payment link")
	}
	paymentURL := strings.TrimSpace(invoiceData.PaylinkURL)
	if paymentURL == "" {
		paymentURL = strings.TrimSpace(invoiceData.SitePay)
	}
	appLink := ""
	if validateAppLink(invoiceData.AppLink, id) == nil {
		appLink = invoiceData.AppLink
	}
	if paymentURL == "" && appLink == "" {
		return Invoice{}, errors.New("O!Dengi did not return a usable payment link")
	}
	if paymentURL != "" {
		if err := validatePaymentURL(paymentURL); err != nil {
			return Invoice{}, errors.New("O!Dengi returned an invalid payment link")
		}
	}
	return Invoice{ID: id, PaymentURL: paymentURL, AppLink: appLink}, nil
}

func GetStatus(ctx context.Context, cfg config.OBankConfig, invoiceID, orderID string) (PaymentStatus, error) {
	data := statusPaymentData{InvoiceID: invoiceID, OrderID: orderID}
	var response apiEnvelope
	if err := call(ctx, cfg, "statusPayment", data, &response); err != nil {
		return PaymentStatus{}, err
	}
	var statusData statusResponseData
	if err := json.Unmarshal(response.Data, &statusData); err != nil {
		return PaymentStatus{}, errors.New("O!Dengi returned an invalid status response")
	}
	status := PaymentStatus{Status: strings.ToLower(strings.TrimSpace(statusData.Status))}
	for _, payment := range statusData.Payments {
		if payment.OrderID != orderID || payment.Test != strconv.Itoa(testFlag(cfg.Test)) {
			continue
		}
		paymentStatus := strings.ToLower(strings.TrimSpace(payment.Status))
		if paymentStatus == "approved" {
			amount, err := strconv.ParseInt(strings.TrimSpace(payment.Amount), 10, 64)
			if err != nil || payment.TransactionID == "" {
				return PaymentStatus{}, errors.New("O!Dengi returned an invalid approved payment")
			}
			return PaymentStatus{Status: paymentStatus, TransactionID: payment.TransactionID, AmountKopecks: amount}, nil
		}
		if paymentStatus == "processing" {
			status.Status = paymentStatus
		}
		if paymentStatus == "canceled" && status.Status == "" {
			status.Status = paymentStatus
		}
	}
	return status, nil
}

func VerifyResult(body []byte, secret string) (Result, error) {
	var payload rawResult
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.UseNumber()
	if err := decoder.Decode(&payload); err != nil {
		return Result{}, errors.New("invalid O!Dengi result payload")
	}
	values := make([]string, 8)
	fields := []json.RawMessage{payload.TransID, payload.Status, payload.SiteID, payload.OrderID, payload.Amount, payload.Currency, payload.Mktime, payload.Test}
	for i, field := range fields {
		value, ok := scalar(field)
		if !ok || value == "" {
			return Result{}, errors.New("incomplete O!Dengi result payload")
		}
		values[i] = value
	}
	providedHash, ok := scalar(payload.Hash)
	if !ok || providedHash == "" {
		return Result{}, errors.New("missing O!Dengi result signature")
	}

	signed := strings.Join(values, ":::")
	expected := hmacMD5Hex([]byte(signed), secret)
	if !hmac.Equal([]byte(strings.ToLower(providedHash)), []byte(expected)) {
		return Result{}, errors.New("invalid O!Dengi result signature")
	}

	status, err := strconv.Atoi(values[1])
	if err != nil {
		return Result{}, errors.New("invalid O!Dengi payment status")
	}
	amount, err := strconv.ParseInt(values[4], 10, 64)
	if err != nil {
		return Result{}, errors.New("invalid O!Dengi payment amount")
	}
	test, err := strconv.Atoi(values[7])
	if err != nil {
		return Result{}, errors.New("invalid O!Dengi test flag")
	}
	invoiceID, _ := scalar(payload.Invoice)
	return Result{
		TransactionID: values[0],
		Status:        status,
		SiteID:        values[2],
		OrderID:       values[3],
		AmountKopecks: amount,
		Currency:      values[5],
		Test:          test,
		InvoiceID:     invoiceID,
	}, nil
}

func call(ctx context.Context, cfg config.OBankConfig, command string, data any, output any) error {
	request := apiRequest{
		Cmd:     command,
		Version: cfg.APIVersion,
		SID:     cfg.SID,
		Mktime:  strconv.FormatInt(time.Now().UnixMilli(), 10),
		Lang:    "ru",
		Data:    data,
	}
	unsignedBody, err := marshalAPIJSON(request)
	if err != nil {
		return errors.New("failed to encode O!Dengi request")
	}
	signed := signedAPIRequest{
		Cmd:     request.Cmd,
		Version: request.Version,
		SID:     request.SID,
		Mktime:  request.Mktime,
		Lang:    request.Lang,
		Data:    request.Data,
		Hash:    hmacMD5Hex(unsignedBody, cfg.Password),
	}
	body, err := marshalAPIJSON(signed)
	if err != nil {
		return errors.New("failed to encode signed O!Dengi request")
	}
	ctx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.APIURL, bytes.NewReader(body))
	if err != nil {
		return errors.New("failed to create O!Dengi request")
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return errors.New("O!Dengi request failed")
	}
	defer resp.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil || len(responseBody) > maxResponseBytes {
		return errors.New("O!Dengi response could not be read")
	}
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("O!Dengi returned HTTP %d", resp.StatusCode)
	}
	if err := json.Unmarshal(responseBody, output); err != nil {
		return errors.New("O!Dengi returned invalid JSON")
	}
	return nil
}

func marshalAPIJSON(value any) ([]byte, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buffer.Bytes(), []byte("\n")), nil
}

func validatePaymentURL(value string) error {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil {
		return errors.New("invalid payment link")
	}
	host := strings.ToLower(parsed.Hostname())
	if host != "dengi.kg" && !strings.HasSuffix(host, ".dengi.kg") {
		return errors.New("unexpected payment host")
	}
	return nil
}

func validateAppLink(value, invoiceID string) error {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "https" || parsed.Host != "o.kg" || parsed.Path != "/l/a" || parsed.User != nil || parsed.Fragment != "" {
		return errors.New("invalid O!Bank app link")
	}
	query := parsed.Query()
	if query.Get("t") != "wl_unpbill" || invoiceID == "" || query.Get("id") != invoiceID {
		return errors.New("O!Bank app link does not match invoice")
	}
	return nil
}

func scalar(raw json.RawMessage) (string, bool) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return "", false
	}
	if trimmed[0] == '"' {
		var value string
		if err := json.Unmarshal(trimmed, &value); err != nil {
			return "", false
		}
		return value, true
	}
	if trimmed[0] == '-' || trimmed[0] >= '0' && trimmed[0] <= '9' {
		return string(trimmed), true
	}
	return "", false
}

func hmacMD5Hex(message []byte, secret string) string {
	hash := hmac.New(md5.New, []byte(secret))
	_, _ = hash.Write(message)
	return hex.EncodeToString(hash.Sum(nil))
}

func testFlag(test bool) int {
	if test {
		return 1
	}
	return 0
}
