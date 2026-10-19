/**
 * JUJ080 従事事業応募登録 コントローラ
 * 設計書：JUJ080 処理詳細 v9・処理項目一覧
 *
 * ※ オブジェクト名・項目名は論理名で記載している（API 名確定後に一括置換する）。
 * ※ 従事事業応募は従事事業の主従子オブジェクトのため、参照範囲は従事事業に従う。
 *   SOQL・DML はすべてユーザモードで実行し、支部の条件は付けない。
 * ※ 他担当の設計に依存する部分（事業の入力フラグ・一括割当実行中）は「Gateway」区画のスタブで実装している。
 * ※ 業務エラーは JujiOboException で発生させ、各メソッドの入口で AuraHandledException に変換する。
 *   例外を画面へ返した時点でトランザクションはロールバックされる。
 * ※ LWC から呼び出すメソッドは、内部クラスを引数・戻り値に使用できないため、以下のとおりとする。
 *   ・引数：プリミティブ型（従事事業キーは3項目に分割、登録リクエストは JSON 文字列）
 *   ・戻り値：Map<String, Object>（内部クラスを JSON 経由で変換。キーは内部クラスの項目名）
 */
public with sharing class JUJ080Controller {

    // ==================== 定数 ====================
    private static final String TYPE_MEMBER = 'MEMBER'; // 会員
    private static final String TYPE_SODANIN = 'SODANIN'; // 相談員

    // 従事可能曜日フラグの値
    @TestVisible
    private static final String WEEKDAY_KA = '可';
    @TestVisible
    private static final String WEEKDAY_FUKA = '不可';

    // 従事可能曜日（画面の値）→ 項目名
    @TestVisible
    private static final List<String> WEEKDAYS = new List<String>{ '日', '月', '火', '水', '木', '金', '土' };
    @TestVisible
    private static final Map<String, String> WEEKDAY_FIELDS = new Map<String, String>{
        '日' => '従事可能曜日フラグ_日__c',
        '月' => '従事可能曜日フラグ_月__c',
        '火' => '従事可能曜日フラグ_火__c',
        '水' => '従事可能曜日フラグ_水__c',
        '木' => '従事可能曜日フラグ_木__c',
        '金' => '従事可能曜日フラグ_金__c',
        '土' => '従事可能曜日フラグ_土__c'
    };

    // 【要確認】スキル項目（8科目）。画面とはこの項目名（API 名）をキーに受け渡す
    @TestVisible
    private static final List<String> SKILL_FIELDS = new List<String>{
        'スキル_所得税__c',
        'スキル_会社法__c',
        'スキル_法人税__c',
        'スキル_財務会計__c',
        'スキル_資産税__c',
        'スキル_譲渡山林__c',
        'スキル_消費税__c',
        'スキル_贈与税__c'
    };

    // 【要確認 QA-20】メッセージ（{メッセージID, 文言}）
    @TestVisible
    private static final List<String> E_JIGYO_NOT_FOUND = new List<String>{ 'JUJ080-E001', '従事事業が存在しません。' };
    @TestVisible
    private static final List<String> E_JUJISHA_NOT_FOUND = new List<String>{ 'WLP007-0009', '従事者が存在しません。' };
    @TestVisible
    private static final List<String> E_NO_JISSHIBI = new List<String>{ 'JUJ080-E002', '実施日が登録されていません。' };
    @TestVisible
    private static final List<String> E_BULK_ASSIGNING = new List<String>{ 'WLP007-0005', '一括割当実行中のため処理できません。' };
    // 追加モードで登録済みの従事者を登録しようとした場合（応募情報表示ボタンの押下を促す）
    @TestVisible
    private static final List<String> E_ALREADY_EXISTS = new List<String>{
        'JUJ080-E003',
        'この従事者の応募情報は既に登録されています。応募情報表示ボタンで登録内容を表示してください。'
    };
    @TestVisible
    private static final List<String> E_DELETED = new List<String>{ 'JUJ080-E004', '他のユーザにより削除されています。' };
    @TestVisible
    private static final List<String> E_UPDATED = new List<String>{ 'JUJ080-E005', '他のユーザにより更新されています。' };
    @TestVisible
    private static final List<String> E_APPLICATION_NOT_FOUND = new List<String>{ 'WLP007-0008', '対象の応募が存在しません。' };
    @TestVisible
    private static final List<String> E_ASSIGNED = new List<String>{ 'WLP007-0006', '割当済みのため削除できません。' };
    @TestVisible
    private static final List<String> E_NO_APPLICATIONS = new List<String>{ 'JUJ080-E006', '削除対象の応募が存在しません。' };

    // 割当のフラグ項目（割当フラグ・確定フラグ）は選択リスト。値 '1' で ON（仮割当・確定）
    @TestVisible
    private static final String FLAG_ON = '1';

    // ==================== 2.(1) 事業の取得 ====================
    // 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName, lastUketukeNo, inputControl } | null }
    @AuraEnabled
    public static Map<String, Object> getJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoKey jigyoKey = toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo);
        JigyoResult result = new JigyoResult();
        // ① 従事場所No が入力されている場合、従事場所名を取得する
        if (String.isNotBlank(jigyoKey.jujiBasyoNo)) {
            従事場所マスタ__c basyo = selectBasyo(jigyoKey.jujiBasyoNo);
            result.basyoName = basyo == null ? null : basyo.従事場所名__c;
        }
        // ② 3項目すべて入力されている場合、従事事業を取得する
        従事事業__c jigyo = selectJigyo(jigyoKey, false);
        if (jigyo != null) {
            result.jigyo = toJigyoInfo(jigyo);
        }
        return toMap(result);
    }

    // ==================== 3.(1) 従事者の取得 ====================
    // 戻り値：従事者情報部。取得できない場合は null（エラーとしない）
    @AuraEnabled
    public static Map<String, Object> getJujisha(String jujishaNo) {
        return toMap(findJujisha(jujishaNo));
    }

    // ==================== 4. 応募情報表示 ====================
    // 戻り値：{ jujisha, application | null }
    @AuraEnabled
    public static Map<String, Object> showApplication(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, String jujishaNo) {
        try {
            従事事業__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), false);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // (1)③ 会員・相談員のいずれからも取得できない場合はエラー
            JujishaInfo jujisha = findJujisha(jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }
            // (3)② 従事事業応募を取得する（取得できない場合は application = null → 追加モード）
            従事事業応募__c app = selectApplicationByJujisha(jigyo.Id, jujisha);
            ShowApplicationResult result = new ShowApplicationResult();
            result.jujisha = jujisha;
            result.application = app == null ? null : toApplicationInfo(app);
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 5・11.(1) 応募情報の読込（応募情報検索からの戻り） ====================
    // 戻り値：{ jigyoKey, jujishaNo, jujisha, application }
    @AuraEnabled
    public static Map<String, Object> getApplication(Id applicationId) {
        try {
            従事事業応募__c app = selectApplicationById(applicationId);
            if (app == null) {
                throw error(E_APPLICATION_NOT_FOUND);
            }
            GetApplicationResult result = new GetApplicationResult();
            result.jigyoKey = toKey(
                app.従事事業__r.従事事業No__c,
                app.従事事業__r.従事場所__r.従事場所No__c,
                app.従事事業__r.実施年度__c
            );
            result.jujishaNo = app.会員__c != null ? app.会員__r.登録番号__c : app.相談員__r.相談員番号__c;
            result.jujisha = findJujisha(result.jujishaNo);
            result.application = toApplicationInfo(app);
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 6.(1) 従事可能日入力前のチェック ====================
    @AuraEnabled
    public static void checkKanoubiInput(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        try {
            従事事業__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), false);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // ② 実施日が1件もない場合はエラー
            if (!hasJisshibi(jigyo.Id)) {
                throw error(E_NO_JISSHIBI);
            }
            // ③ 一括割当実行中の場合はエラー
            if (isBulkAssigning(jigyo.Id)) {
                throw error(E_BULK_ASSIGNING);
            }
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 7.(3) 登録処理 ====================
    // 引数：SaveRequest の JSON 文字列
    // 戻り値：{ uketukeNo }（採番しなかった場合は null）
    @AuraEnabled
    public static Map<String, Object> saveApplication(String requestJson) {
        try {
            SaveRequest request = (SaveRequest) JSON.deserialize(requestJson, SaveRequest.class);
            // 応募IDを保持していない場合は追加モード
            Boolean isAdd = request.applicationId == null;

            // ① 従事事業を取得してロックする。取得後、一括割当実行中を再チェックする
            従事事業__c jigyo = selectJigyo(request.jigyoKey, true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            if (isBulkAssigning(jigyo.Id)) {
                throw error(E_BULK_ASSIGNING);
            }

            // ② 従事者を取得する
            JujishaInfo jujisha = findJujisha(request.jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }

            // ③ 従事事業応募を取得する
            従事事業応募__c existing = selectApplicationByJujisha(jigyo.Id, jujisha);
            if (isAdd && existing != null) {
                throw error(E_ALREADY_EXISTS); // a. 同じ従事者の応募が登録済み
            }
            if (!isAdd && existing == null) {
                throw error(E_DELETED); // b. 他のユーザにより削除済み
            }
            if (!isAdd && existing.LastModifiedDate != request.lastModifiedDate) {
                throw error(E_UPDATED); // c. 他のユーザにより更新済み
            }

            // ④ 追加モード、または受付番号が 0 の場合は採番する
            Decimal uketukeNo = null;
            if (isAdd || existing.受付番号__c == null || existing.受付番号__c == 0) {
                uketukeNo = selectMaxUketukeNo(jigyo.Id) + 1;
            }

            // ⑤ 従事事業応募を登録する
            従事事業応募__c rec;
            if (isAdd) {
                // a. 追加モード：従事事業・会員または相談員を設定して新規作成
                rec = new 従事事業応募__c(従事事業__c = jigyo.Id);
                if (jujisha.jujishaType == TYPE_MEMBER) {
                    rec.会員__c = jujisha.recordId;
                } else {
                    rec.相談員__c = jujisha.recordId;
                }
            } else {
                // b. 変更モード：従事事業・会員・相談員は更新しない
                rec = new 従事事業応募__c(Id = existing.Id);
            }
            if (uketukeNo != null) {
                rec.受付番号__c = uketukeNo;
            }
            applyForm(rec, request.form);
            if (isAdd) {
                Database.insert(rec, AccessLevel.USER_MODE);
            } else {
                Database.update(rec, AccessLevel.USER_MODE);
            }

            // ⑥ 従事可能日（従事事業応募明細）を登録する。日付ごとに1件とし、選択した時間帯を JSON で設定する
            // b. 変更モード：既存の明細をすべて削除してから追加する
            if (!isAdd && !existing.従事事業応募明細__r.isEmpty()) {
                Database.delete(existing.従事事業応募明細__r, AccessLevel.USER_MODE);
            }
            List<従事事業応募明細__c> details = new List<従事事業応募明細__c>();
            if (request.kanoubiDates != null) {
                for (KanoubiDate kanoubi : request.kanoubiDates) {
                    details.add(
                        new 従事事業応募明細__c(
                            従事事業応募__c = rec.Id,
                            従事事業__c = jigyo.Id,
                            従事可能日__c = Date.valueOf(kanoubi.kanoubiDate),
                            時間帯__c = JSON.serialize(kanoubi.timeSlots == null ? new List<TimeSlot>() : kanoubi.timeSlots)
                        )
                    );
                }
            }
            if (!details.isEmpty()) {
                Database.insert(details, AccessLevel.USER_MODE);
            }

            // (4)① 採番した場合のみ受付番号を返す
            SaveResult result = new SaveResult();
            result.uketukeNo = uketukeNo;
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 8.(2) 削除処理 ====================
    @AuraEnabled
    public static void deleteApplication(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, String jujishaNo) {
        try {
            // ① 従事事業を取得してロックする
            従事事業__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // ② 一括割当実行中の場合はエラー
            if (isBulkAssigning(jigyo.Id)) {
                throw error(E_BULK_ASSIGNING);
            }
            // ③ 従事者を取得する
            JujishaInfo jujisha = findJujisha(jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }
            // ④ 従事事業応募を取得する
            従事事業応募__c app = selectApplicationByJujisha(jigyo.Id, jujisha);
            if (app == null) {
                throw error(E_APPLICATION_NOT_FOUND);
            }
            // ⑤ 割当（仮割当を含む）が存在する場合はエラー
            if (hasAssignment(jigyo.Id, new List<従事事業応募__c>{ app })) {
                throw error(E_ASSIGNED);
            }
            // ⑥ 削除する（明細は主従関係により同時に削除される）
            Database.delete(new 従事事業応募__c(Id = app.Id), AccessLevel.USER_MODE);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 9.(3) 全削除処理 ====================
    @AuraEnabled
    public static void deleteAllApplications(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        try {
            // ① 従事事業を取得してロックする
            従事事業__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // ② 一括割当実行中の場合はエラー
            if (isBulkAssigning(jigyo.Id)) {
                throw error(E_BULK_ASSIGNING);
            }
            // ③ 従事事業応募を取得する。1件もない場合はエラー
            List<従事事業応募__c> apps = [
                SELECT Id, 会員__c, 相談員__c
                FROM 従事事業応募__c
                WHERE 従事事業__c = :jigyo.Id
                WITH USER_MODE
            ];
            if (apps.isEmpty()) {
                throw error(E_NO_APPLICATIONS);
            }
            // ④ 1件でも割当が存在する場合はエラーとし、1件も削除しない
            if (hasAssignment(jigyo.Id, apps)) {
                throw error(E_ASSIGNED);
            }
            // ⑤ すべて削除する（明細は主従関係により同時に削除される）
            Database.delete(apps, AccessLevel.USER_MODE);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== Selector ====================
    // 従事場所マスタ
    private static 従事場所マスタ__c selectBasyo(String basyoNo) {
        List<従事場所マスタ__c> recs = [
            SELECT Id, 従事場所名__c
            FROM 従事場所マスタ__c
            WHERE 従事場所No__c = :basyoNo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事事業（事業キーで取得。forUpdate＝true の場合はロックする）
    private static 従事事業__c selectJigyo(JigyoKey key, Boolean forUpdate) {
        // キーが揃っていない場合はクエリを発行しない
        if (key == null || !key.isComplete()) {
            return null;
        }
        String soql =
            'SELECT Id, 従事事業名__c, 支部__r.支部コード__c, 支部__r.Name' +
            ' FROM 従事事業__c' +
            ' WHERE 従事事業No__c = :jigyoNo' +
            ' AND 従事場所__r.従事場所No__c = :basyoNo' +
            ' AND 実施年度__c = :nendo' +
            ' LIMIT 1' +
            (forUpdate ? ' FOR UPDATE' : '');
        Map<String, Object> binds = new Map<String, Object>{
            'jigyoNo' => key.jujiJigyoNo,
            'basyoNo' => key.jujiBasyoNo,
            'nendo' => key.jisiNendo
        };
        List<従事事業__c> recs = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        return recs.isEmpty() ? null : recs[0];
    }

    // 受付番号の最大値（応募がない場合は 0）
    private static Decimal selectMaxUketukeNo(Id jigyoId) {
        List<AggregateResult> results = [
            SELECT MAX(受付番号__c) maxNo
            FROM 従事事業応募__c
            WHERE 従事事業__c = :jigyoId
            WITH USER_MODE
        ];
        Decimal maxNo = (Decimal) results[0].get('maxNo');
        return maxNo == null ? 0 : maxNo;
    }

    // 従事者の取得（会員 → 相談員の順。取得できない場合は null）
    private static JujishaInfo findJujisha(String jujishaNo) {
        if (String.isBlank(jujishaNo)) {
            return null;
        }
        // a. 会員から取得する
        //    会員は取引先責任者（Contact）。氏名は標準項目 Name、フリガナは姓・名の2項目を連結する
        //    支部コード・支部名・事務所住所・事務所電話番号・事務所FAX番号は参照先の事務所・法人（Account）から取得する
        List<Contact> members = [
            SELECT Id, 登録番号__c, Name, フリガナ_姓__c, フリガナ_名__c,
                事務所__r.支部コード__c, 事務所__r.Name,
                事務所__r.事務所住所__c, 事務所__r.事務所電話番号__c, 事務所__r.事務所FAX番号__c
            FROM Contact
            WHERE 登録番号__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!members.isEmpty()) {
            Contact m = members[0];
            JujishaInfo info = new JujishaInfo();
            info.jujishaType = TYPE_MEMBER;
            info.recordId = m.Id;
            info.jujishaNo = m.登録番号__c;
            info.name = m.Name;
            info.furigana = joinName(m.フリガナ_姓__c, m.フリガナ_名__c);
            info.shibuCode = m.事務所__r?.支部コード__c;
            info.shibuName = m.事務所__r?.Name; // 支部名＝事務所・法人の名称
            info.address = m.事務所__r?.事務所住所__c;
            info.tel = m.事務所__r?.事務所電話番号__c;
            info.fax = m.事務所__r?.事務所FAX番号__c;
            return info;
        }
        // b. a で取得できない場合、相談員から取得する（相談員の場合、支部コード・支部名は空白）
        List<相談員__c> sodanins = [
            SELECT Id, 相談員番号__c, 氏名__c, フリガナ__c, 事務所住所__c, 事務所電話番号__c, 事務所FAX番号__c
            FROM 相談員__c
            WHERE 相談員番号__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!sodanins.isEmpty()) {
            相談員__c s = sodanins[0];
            JujishaInfo info = new JujishaInfo();
            info.jujishaType = TYPE_SODANIN;
            info.recordId = s.Id;
            info.jujishaNo = s.相談員番号__c;
            info.name = s.氏名__c;
            info.furigana = s.フリガナ__c;
            info.address = s.事務所住所__c;
            info.tel = s.事務所電話番号__c;
            info.fax = s.事務所FAX番号__c;
            return info;
        }
        return null;
    }

    // 従事事業応募（応募IDで取得）
    private static 従事事業応募__c selectApplicationById(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<従事事業応募__c> recs = Database.queryWithBinds(
            applicationSoql('Id = :applicationId'),
            new Map<String, Object>{ 'applicationId' => applicationId },
            AccessLevel.USER_MODE
        );
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事事業応募（事業＋従事者で取得）
    private static 従事事業応募__c selectApplicationByJujisha(Id jigyoId, JujishaInfo jujisha) {
        // 応募は会員・相談員のどちらか一方のみ設定されるため、もう一方は null（IS NULL）で検索する
        Map<String, Object> binds = new Map<String, Object>{
            'jigyoId' => jigyoId,
            'memberId' => jujisha.jujishaType == TYPE_MEMBER ? jujisha.recordId : null,
            'sodaninId' => jujisha.jujishaType == TYPE_SODANIN ? jujisha.recordId : null
        };
        List<従事事業応募__c> recs = Database.queryWithBinds(
            applicationSoql('従事事業__c = :jigyoId AND 会員__c = :memberId AND 相談員__c = :sodaninId'),
            binds,
            AccessLevel.USER_MODE
        );
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事事業応募の取得 SOQL（従事可能日の明細を含む）
    private static String applicationSoql(String whereClause) {
        List<String> fields = new List<String>{
            'Id',
            '受付番号__c',
            'LastModifiedDate',
            '会員__c',
            '会員__r.登録番号__c',
            '相談員__c',
            '相談員__r.相談員番号__c',
            '従事事業__r.従事事業No__c',
            '従事事業__r.従事場所__r.従事場所No__c',
            '従事事業__r.実施年度__c',
            '連絡先_固定電話__c',
            '連絡先_携帯電話__c',
            '連絡先_FAX__c',
            '連絡先_Mail__c',
            '備考__c',
            '希望従事日数__c',
            '従事経験__c',
            'スキル特記事項__c',
            '主な著書論文__c',
            '相談科目__c'
        };
        fields.addAll(WEEKDAY_FIELDS.values());
        fields.addAll(SKILL_FIELDS);
        return 'SELECT ' + String.join(fields, ', ') +
            ', (SELECT Id, 従事可能日__c, 時間帯__c FROM 従事事業応募明細__r ORDER BY 従事可能日__c)' +
            ' FROM 従事事業応募__c' +
            ' WHERE ' + whereClause +
            ' LIMIT 1';
    }

    // ==================== 変換 ====================
    // 従事事業キー（3項目）
    private static JigyoKey toKey(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoKey key = new JigyoKey();
        key.jujiJigyoNo = jujiJigyoNo;
        key.jujiBasyoNo = jujiBasyoNo;
        key.jisiNendo = jisiNendo;
        return key;
    }

    // 姓・名を半角スペースで連結する（いずれかが空の場合は空でない方のみ）
    @TestVisible
    private static String joinName(String sei, String mei) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(sei)) {
            parts.add(sei);
        }
        if (String.isNotBlank(mei)) {
            parts.add(mei);
        }
        return String.join(parts, ' ');
    }

    // 内部クラス → 画面へ返す Map（JSON 経由で変換。transient の項目は含まれない）
    @TestVisible
    private static Map<String, Object> toMap(Object dto) {
        if (dto == null) {
            return null;
        }
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto));
    }

    // 時間帯 JSON → 時間帯リスト（未設定・形式不正の場合は空。使用しない項目は無視する）
    @TestVisible
    private static List<TimeSlot> parseTimeSlots(String value) {
        if (String.isBlank(value)) {
            return new List<TimeSlot>();
        }
        try {
            return (List<TimeSlot>) JSON.deserialize(value, List<TimeSlot>.class);
        } catch (JSONException e) {
            return new List<TimeSlot>();
        }
    }

    // 従事事業 → 画面表示用
    private static JigyoInfo toJigyoInfo(従事事業__c jigyo) {
        JigyoInfo info = new JigyoInfo();
        info.jigyoName = jigyo.従事事業名__c;
        info.shibuCode = jigyo.支部__r?.支部コード__c;
        info.shibuName = jigyo.支部__r?.Name;
        // 最終受付番号：受付番号の最大値（0 または応募なしの場合は空白）
        Decimal maxNo = selectMaxUketukeNo(jigyo.Id);
        info.lastUketukeNo = maxNo == 0 ? null : maxNo;
        info.inputControl = getInputControl(jigyo);
        return info;
    }

    // 従事事業応募 → 画面表示用（11.(1)）
    private static ApplicationInfo toApplicationInfo(従事事業応募__c app) {
        ApplicationForm form = new ApplicationForm();
        form.telFixed = app.連絡先_固定電話__c;
        form.telMobile = app.連絡先_携帯電話__c;
        form.fax = app.連絡先_FAX__c;
        form.mail = app.連絡先_Mail__c;
        form.biko = app.備考__c;
        // 【要確認 QA-17④】全日程従事可能は専用項目を持たない（登録時に全曜日を「可」とする）ため、読込時は OFF とする
        form.allDays = false;
        form.weekdays = new List<String>();
        for (String day : WEEKDAYS) {
            if (app.get(WEEKDAY_FIELDS.get(day)) == WEEKDAY_KA) {
                form.weekdays.add(day);
            }
        }
        form.kibouNissu = app.希望従事日数__c == null ? null : String.valueOf(app.希望従事日数__c);
        form.keiken = app.従事経験__c; // 【要確認】項目の値（'1'＝有 / '0'＝無）
        form.skills = new List<SkillValue>();
        for (String field : SKILL_FIELDS) {
            String value = (String) app.get(field);
            if (String.isNotBlank(value)) {
                SkillValue skill = new SkillValue();
                skill.field = field;
                skill.value = value;
                form.skills.add(skill);
            }
        }
        form.skillNote = app.スキル特記事項__c;
        form.chosho = app.主な著書論文__c;
        form.sodanKamoku = app.相談科目__c;

        ApplicationInfo info = new ApplicationInfo();
        info.applicationId = app.Id;
        info.uketukeNo = app.受付番号__c;
        info.lastModifiedDate = app.LastModifiedDate; // 7.(3)③c の更新確認に使用
        info.form = form;
        info.kanoubiDates = new List<KanoubiDate>();
        for (従事事業応募明細__c detail : app.従事事業応募明細__r) {
            KanoubiDate kanoubi = new KanoubiDate();
            kanoubi.kanoubiDate = String.valueOf(detail.従事可能日__c); // 'yyyy-MM-dd'
            kanoubi.timeSlots = parseTimeSlots(detail.時間帯__c);
            info.kanoubiDates.add(kanoubi);
        }
        return info;
    }

    // 画面の入力値 → 従事事業応募
    private static void applyForm(従事事業応募__c rec, ApplicationForm form) {
        if (form == null) {
            form = new ApplicationForm();
        }
        rec.連絡先_固定電話__c = form.telFixed;
        rec.連絡先_携帯電話__c = form.telMobile;
        rec.連絡先_FAX__c = form.fax;
        rec.連絡先_Mail__c = form.mail;
        rec.備考__c = form.biko;
        // 従事可能曜日：全日程従事可能が ON の場合はすべて「可」とする（7.(3)⑤c）
        Set<String> weekdays = form.weekdays == null ? new Set<String>() : new Set<String>(form.weekdays);
        for (String day : WEEKDAYS) {
            Boolean isKa = form.allDays == true || weekdays.contains(day);
            rec.put(WEEKDAY_FIELDS.get(day), isKa ? WEEKDAY_KA : WEEKDAY_FUKA);
        }
        rec.希望従事日数__c = String.isBlank(form.kibouNissu) ? null : Decimal.valueOf(form.kibouNissu);
        rec.従事経験__c = form.keiken;
        // スキル：画面から受け取った項目名が SKILL_FIELDS に含まれるもののみ設定し、値が選択されていない科目は空とする
        Map<String, String> skillValues = new Map<String, String>();
        if (form.skills != null) {
            for (SkillValue skill : form.skills) {
                skillValues.put(skill.field, skill.value);
            }
        }
        for (String field : SKILL_FIELDS) {
            String value = skillValues.get(field);
            rec.put(field, String.isBlank(value) ? null : value);
        }
        rec.スキル特記事項__c = form.skillNote;
        rec.主な著書論文__c = form.chosho;
        rec.相談科目__c = form.sodanKamoku;
    }

    // ==================== Gateway（他担当の設計に依存する部分） ====================
    // 【要確認 QA-16】事業の必須／任意入力フラグ。項目確定までは「必須なし・すべて入力可」として返す
    private static InputControl getInputControl(従事事業__c jigyo) {
        InputControl ctrl = new InputControl();
        ctrl.requiredWeekday = false;
        ctrl.requiredKanoubi = false;
        ctrl.requiredKibouNissu = false;
        ctrl.requiredSkill = false;
        ctrl.optionalSkill = true;
        ctrl.optionalSkillNote = true;
        ctrl.optionalChosho = true;
        ctrl.optionalSodanKamoku = true;
        return ctrl;
    }

    // 実施日（従事事業明細）が1件以上あるか
    private static Boolean hasJisshibi(Id jigyoId) {
        return [SELECT COUNT() FROM 従事事業明細__c WHERE 従事事業__c = :jigyoId WITH USER_MODE] > 0;
    }

    // 【要確認 QA-15】一括割当実行中か。割当担当の回答までは常に false
    private static Boolean isBulkAssigning(Id jigyoId) {
        return false;
    }

    // 応募の従事者に、同じ事業の割当（仮割当を含む）が存在するか（8.(2)⑤・9.(3)④）
    // ※ 割当は従事事業の主従子オブジェクトで、会員・相談員を参照する（応募への参照はない）
    //   仮割当＝割当フラグ＝1、確定＝確定フラグ＝1
    private static Boolean hasAssignment(Id jigyoId, List<従事事業応募__c> apps) {
        Set<Id> memberIds = new Set<Id>();
        Set<Id> sodaninIds = new Set<Id>();
        for (従事事業応募__c app : apps) {
            if (app.会員__c != null) {
                memberIds.add(app.会員__c);
            }
            if (app.相談員__c != null) {
                sodaninIds.add(app.相談員__c);
            }
        }
        if (memberIds.isEmpty() && sodaninIds.isEmpty()) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM 従事事業割当__c
            WHERE 従事事業__c = :jigyoId
            AND (割当フラグ__c = :FLAG_ON OR 確定フラグ__c = :FLAG_ON)
            AND (会員__c IN :memberIds OR 相談員__c IN :sodaninIds)
            WITH USER_MODE
        ] > 0;
    }

    // ==================== 例外 ====================
    // 業務エラー（メッセージID 付き）
    public class JujiOboException extends Exception {
        public String messageId;
    }

    private static JujiOboException error(List<String> msg) {
        JujiOboException e = new JujiOboException(msg[1]);
        e.messageId = msg[0];
        return e;
    }

    // 画面へ返す例外に変換する（setMessage しないと画面に文言が渡らない）
    private static AuraHandledException toAuraException(JujiOboException e) {
        AuraHandledException ae = new AuraHandledException(e.getMessage());
        ae.setMessage(e.getMessage());
        return ae;
    }

    // ==================== DTO（クラス内部でのみ使用。画面との受渡しは JSON・Map 経由） ====================
    // 従事事業キー
    public class JigyoKey {
        public String jujiJigyoNo;
        public String jujiBasyoNo;
        public String jisiNendo;

        // 3項目すべて入力されているか
        public Boolean isComplete() {
            return String.isNotBlank(jujiJigyoNo) && String.isNotBlank(jujiBasyoNo) && String.isNotBlank(jisiNendo);
        }
    }

    public class JigyoResult {
        public String basyoName;
        public JigyoInfo jigyo;
    }

    public class JigyoInfo {
        public String jigyoName;
        public String shibuCode;
        public String shibuName;
        public Decimal lastUketukeNo;
        public InputControl inputControl;
    }

    // 事業設定による入力制御
    public class InputControl {
        public Boolean requiredWeekday;
        public Boolean requiredKanoubi;
        public Boolean requiredKibouNissu;
        public Boolean requiredSkill;
        public Boolean optionalSkill;
        public Boolean optionalSkillNote;
        public Boolean optionalChosho;
        public Boolean optionalSodanKamoku;
    }

    // 従事者情報部
    public class JujishaInfo {
        public String jujishaType;
        public String jujishaNo;
        public String name;
        public String furigana;
        public String shibuCode;
        public String shibuName;
        public String address;
        public String tel;
        public String fax;
        // 会員ID または相談員ID（サーバ内部でのみ使用。transient のため画面には返さない）
        public transient Id recordId;
    }

    public class ShowApplicationResult {
        public JujishaInfo jujisha;
        public ApplicationInfo application;
    }

    public class GetApplicationResult {
        public JigyoKey jigyoKey;
        public String jujishaNo;
        public JujishaInfo jujisha;
        public ApplicationInfo application;
    }

    // 応募情報（受付番号・応募情報部・従事可能日）
    public class ApplicationInfo {
        public Id applicationId;
        public Decimal uketukeNo;
        public Datetime lastModifiedDate;
        public ApplicationForm form;
        public List<KanoubiDate> kanoubiDates;
    }

    // 従事可能日（日付と選択した時間帯）
    public class KanoubiDate {
        public String kanoubiDate; // 'yyyy-MM-dd'
        public List<TimeSlot> timeSlots;
    }

    // 時間帯（応募明細の時間帯項目に JSON で保持する。開始時間＋終了時間で同一判定する）
    public class TimeSlot {
        public String startTime; // 'HH:mm'
        public String endTime; // 'HH:mm'
    }

    // 応募情報部
    public class ApplicationForm {
        public String telFixed;
        public String telMobile;
        public String fax;
        public String mail;
        public String biko;
        public Boolean allDays;
        public List<String> weekdays;
        public String kibouNissu;
        public String keiken;
        public List<SkillValue> skills;
        public String skillNote;
        public String chosho;
        public String sodanKamoku;
    }

    // スキル（項目名・選択値）
    public class SkillValue {
        public String field;
        public String value;
    }

    // 登録リクエスト
    public class SaveRequest {
        public JigyoKey jigyoKey;
        public String jujishaNo;
        public Id applicationId;
        public Datetime lastModifiedDate;
        public ApplicationForm form;
        public List<KanoubiDate> kanoubiDates;
    }

    public class SaveResult {
        public Decimal uketukeNo;
    }
}
