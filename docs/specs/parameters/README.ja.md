# プロトコルを読めるようにする

[English](README.md) | **日本語**

SIOP アプリ・テスト RP ともに最優先は、人がプロトコルのパラメータを理解できること。
実際の値、それぞれの出どころ、リクエスト・応答・検証の期待値の対応関係。UI の他の要素は
すべてこの後に来る。

## 現状

両側の要件で、今のところ [HTML UI モック](../../../rp/public/mock.html)だけが満たしている。
モックは一時的なメモリ上の鍵に対して実際の WebCrypto 処理を行い、外部 RP には送信しない。
意図する振る舞いのデモであって、実装でも相互運用テストでもない。

## 制約

この主題が求めるものの大半は、ある瞬間ではなく常に成り立つ話なので、シナリオではなく
要件の文で書く。

- The SIOP app shall show each parameter of a received request with the value that arrived, not a
  normalised or re-encoded form of it.
  (受け取ったリクエストの各パラメータは、届いた値そのままで見せる。正規化や再エンコードをしない)
- The SIOP app shall distinguish values that came from the Relying Party from values the device
  produced.
  (RP から来た値と、端末が作った値を区別できるようにする)
- The RP shall show each parameter of a request with the value it will send, before it is sent.
  (RP は送信前に、各パラメータを実際に送る値とともに見せる)
- The RP shall mark the parameters it will check the response against.
  (応答の照合に使うパラメータが、どれかわかるようにする)
- The RP shall report each Section 7.5 check on its own, and shall not reduce the result to a
  single pass or fail.
  (7.5 の各検査を個別に報告する。全体の合否ひとつにまとめない)
- The RP shall make the ID Token available in its encoded form and as a decoded header and
  payload.
  (ID Token を、エンコードされた形と、デコードしたヘッダ・ペイロードの両方で取り出せるようにする)
- Where a value is derived rather than received, the app showing it shall say what it was derived
  from.
  (受け取ったのではなく導出した値は、何から導いたかを示す)

## 振る舞い

```gherkin
Feature: Reading a verification result

  Scenario: Comparing a response against what was expected
    Given the RP has received an ID Token
    When the verification result is shown
    Then each checked claim is shown beside the value that was expected

  Scenario: A check that fails
    Given a response whose nonce does not match the request
    When the verification result is shown
    Then the failing check is named
    And the received value and the expected value are both shown
    And the checks that passed are still shown as passed
```

## テストで見るもの

7.5 の各検査が正しい判定に至るかは、`rp/test/verify.test.mjs` と各実装の検証器テストが
判定する。ここで規定しているのは、人がその値と判定を見られることだけ。
