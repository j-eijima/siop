# 同意と応答のプレビュー

[English](README.md) | **日本語**

署名する前に、何に署名してどこへ送るのかをユーザーが見ている。ここは人が必ず読む唯一の画面なので、
実装任せにせず仕様として書く。

## 現状

iOS で実装済み。同意画面は届いたリクエストをそのまま示し、応答に使う識別子を選ぶか作らせ
([identity/](../identity/))、公開鍵を含めて署名される値をすべて、それぞれの出どころとともに
プレビューする([parameters/](../parameters/))。拒否時の `access_denied` は両プラットフォームで
返している。Android の同意画面は、要求元の `client_id`、要求された scope、`response_type`、
`nonce`、`state`、そしてその RP に対して確立済みの `sub`(無ければ応答時に作る旨)を出すが、
公開鍵は出さず、識別子の選択もない。

## 振る舞い

```gherkin
Feature: Consent and the response preview

  Background:
    Given a Relying Party has sent an authentication request to openid://

  Scenario: Showing what is about to be signed
    Given an identity on this device has already answered this Relying Party
    When the app asks the user whether to respond
    Then the client_id that sent the request is shown as it arrived
    And the redirect URI the response will be sent to is shown
    And the subject identifier that will appear in sub is shown
    And the public key that will travel as sub_jwk is shown

  Scenario: A Relying Party that has not been answered before
    Given no identity on this device has answered this Relying Party
    When the app asks the user whether to respond
    Then the client_id and the redirect URI are shown as above
    And the app says a new subject will be created if the user responds
    And no subject or public key is shown, because none exists yet

  Scenario: Declining
    When the user declines
    Then error=access_denied is returned to the Relying Party through the redirect URI
    And the app says which Relying Party was answered that way

  Scenario: Approving
    When the user approves
    Then the ID Token is handed back through the redirect URI that was shown

  Scenario: A response that cannot be delivered
    Given nothing on the device can open the redirect URI
    When the user approves
    Then the app says the ID Token was issued and did not reach the Relying Party
```

## 制約

- The SIOP app shall not create a signing key for a Relying Party before the user has responded to
  that Relying Party.
  (その RP 用の鍵を作るのは応答した時。リクエストが届いただけでは作らない)
- The SIOP app shall not issue an ID Token the user has not approved. Declining is an answer, not
  silence: the Relying Party is told, and told only that.
  (承認していないトークンは発行しない。拒否は沈黙ではなく応答で、RP にはそれだけが伝わる)
- If the request is missing a parameter the OP requires, then the SIOP app shall name the missing
  parameter and shall not ask for consent.
  (必須パラメータが欠けていたら、どれが欠けているかを示し、同意を求めない)
- If the request cannot be parsed at all, then the SIOP app shall say so and shall not contact the
  redirect URI it failed to read.
  (解釈できないリクエストは、そう表示し、読めなかった redirect URI に接続しない)
- While the app is waiting for the user's answer, the SIOP app shall show the values it will sign
  rather than a summary of them.
  (待っている間に見せるのは、署名する実際の値であって要約ではない)

## テストで見るもの

RP が受け取ったトークンが 7.5 の検証を通ることは、`ios/SIOPApp/UITests/EndToEndRPTests.swift`
と `rp/test/` の実装横断スイートが end-to-end で判定する。上のシナリオは応答がアプリを
出るところで終わる。
