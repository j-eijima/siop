# 識別子の管理と選択

[English](README.md) | **日本語**

識別子とは、署名鍵とそこから導出される `sub` の組。ユーザーは複数を持て、どの RP に
どれで応答するかを選べる。

## 現状

iOS で実装済み。Android は今も `client_id` ごとに別の鍵を持って自動で使うため、pairwise な
`sub` は成立しているが、ユーザーに選択肢は出ていない。iOS では、RP ごとの鍵の版が作った鍵を、
その RP から次にリクエストが来たときに識別子として引き継ぐ。ある RP に紐づいていた識別子は
紐づいたままになる。同じ形を [UI モック](../../../rp/public/mock.html)が一時的なメモリ上の鍵で
示している。

## 振る舞い

```gherkin
Feature: Identity management and selection

  Background:
    Given the SIOP app is installed on the device

  Scenario: Listing identities
    When the user opens the identity list
    Then every identity is listed with its label and its subject identifier
    And each identity shows which Relying Parties it has answered

  Scenario: Creating an identity
    When the user creates an identity and gives it a label
    Then a new signing key is generated on the device
    And the subject identifier shown is the JWK thumbprint of that key's public part

  Scenario: Inspecting an identity
    When the user opens an identity from the list
    Then the subject identifier is shown
    And the public key is shown as it will appear in sub_jwk
    And the Relying Parties this identity has answered are shown

  Scenario: Editing an identity
    When the user edits an identity
    Then the label and the note can be changed

  Scenario: Deleting an identity
    When the user deletes an identity
    Then the app states that the signing key is removed
    And the app states that this identity can never answer again unless the key is restored
    And the app states that the account the Relying Party holds is not deleted
    And the deletion takes a second, explicit confirmation

  Scenario: Choosing which identity answers a request
    Given an authentication request has arrived from a Relying Party
    When the user is asked whether to respond
    Then the identity used for the response can be changed before signing
    And the identity that has already answered this Relying Party is the one offered first

  Scenario: Answering a Relying Party for the first time
    Given the Relying Party has never been answered from this device
    When the user is asked whether to respond
    Then the app says that responding creates a new identity for this Relying Party
```

## 制約

- The SIOP app shall derive an identity's subject identifier from its public key, and shall not
  accept a subject identifier as input.
  (`sub` は公開鍵から導出するものであり、入力として受け取らない)
- While an identity is being edited, the SIOP app shall not alter its signing key.
  (編集で変わるのは表示名とメモだけで、鍵には触れない)
- The SIOP app shall keep an identity's association with a Relying Party until the user changes it.
  (RP との紐づきは、ユーザーが変えない限り保つ)
- If a signing key cannot be read from the device's key store, then the SIOP app shall show the
  identity as unusable rather than omitting it from the list.
  (鍵が読めない識別子は、一覧から消さずに使用不可として見せる)
- If a Relying Party has an identity whose signing key cannot be read, then the SIOP app shall not
  answer that Relying Party as a new identity unless the user creates one.
  (識別子があるのに鍵が読めない RP には、利用者が自分で作らない限り、新しい識別子で応答しない)

## テストで見るもの

`sub` が公開鍵の RFC 7638 サムプリントであること、RP が違えば別の `sub` を受け取ることは、
各実装のユニットテストが判定する。ここにシナリオとして重ねて書かない。
