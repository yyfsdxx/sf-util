/**
 * JUJ080 従事事業応募登録 コントローラ
 * ※ 従事事業応募明細は1件＝1従事可能日の1時間帯（開始時間・終了時間）。
 *   画面とは日付ごと（kanoubiDates: [{ kanoubiDate, timeSlots: [{ startTime, endTime }] }]）に受け渡し、本クラスで変換する。
 *   変更モードの登録では、変更のあった時間帯のみ削除・登録する（変わらない時間帯はそのまま残す）。
 * ※ 排他チェック：応募は共通部品、応募明細は件数＋最新のシステム更新日時（明細の版）で行う。
 * ※ 参照範囲は共有設定に従う（SOQL・DML はユーザモードで実行し、支部の条件は付けない）。
 * ※ 業務エラーは JujiOboException で発生させ、AuraHandledException に変換して画面へ返す。
 *   一括割当実行中・排他のチェックは共通部品（Juj_CommonController）が AuraHandledException を発生させる。
 *   いずれもトランザクションはロールバックされる。
 * ※ LWC との受け渡しは、引数を基本型または JSON 文字列、戻り値を Map とする。
 */
public with sharing class Juj_JigyoOboTourokuController {

    private static final String TYPE_MEMBER = 'MEMBER'; // 会員
    private static final String TYPE_SODANIN = 'SODANIN'; // 相談員

    // 従事可能曜日フラグの値（API 参照名。表示ラベルは 1＝可、0＝不可）
    @TestVisible
    private static final String WEEKDAY_KA = '1';
    @TestVisible
    private static final String WEEKDAY_FUKA = '0';

    // 従事可能曜日（画面の値）と従事可能曜日フラグの項目
    @TestVisible
    private static final List<String> WEEKDAYS = new List<String>{ '日', '月', '火', '水', '木', '金', '土' };
    @TestVisible
    private static final Map<String, String> WEEKDAY_FIELDS = new Map<String, String>{
        '日' => 'Oubo_Juji_Kano_Yobi_Flag_Sun__c',
        '月' => 'Oubo_Juji_Kano_Yobi_Flag_Mon__c',
        '火' => 'Oubo_Juji_Kano_Yobi_Flag_Tue__c',
        '水' => 'Oubo_Juji_Kano_Yobi_Flag_Wed__c',
        '木' => 'Oubo_Juji_Kano_Yobi_Flag_Thu__c',
        '金' => 'Oubo_Juji_Kano_Yobi_Flag_Fri__c',
        '土' => 'Oubo_Juji_Kano_Yobi_Flag_Sat__c'
    };

    // スキル（8科目）の項目。画面とは項目の API 名をキーに受け渡す
    @TestVisible
    private static final List<String> SKILL_FIELDS = new List<String>{
        'Oubo_Skill_Syotoku_Zei__c', // 所得税
        'Oubo_Skill_Kaisyaho__c', // 会社法
        'Oubo_Skill_Hojin_Zei__c', // 法人税
        'Oubo_Skill_Zaimu_Kaikei__c', // 財務会計
        'Oubo_Skill_Sisan_Zei__c', // 資産税
        'Oubo_Skill_Joto_Sanrin__c', // 譲渡山林
        'Oubo_Skill_Syohi_Zei__c', // 消費税
        'Oubo_Skill_Zoyo_Zei__c' // 贈与税
    };

    // メッセージ（{メッセージID, 文言}）。末尾は 4.入力チェックの No.【要確認 QA-20】ID は暫定
    @TestVisible
    private static final List<String> E_JIGYO_NOT_FOUND = new List<String>{ 'JUJ080-E001', '従事事業が存在しません。' }; // No.16
    @TestVisible
    private static final List<String> E_JUJISHA_NOT_FOUND = new List<String>{ 'WLP007-0009', '従事者が存在しません。' }; // No.17
    @TestVisible
    private static final List<String> E_NO_JISSHIBI = new List<String>{ 'JUJ080-E002', '実施日が登録されていません。' }; // No.14
    @TestVisible
    private static final List<String> E_ALREADY_EXISTS = new List<String>{
        'JUJ080-E003',
        '指定された従事者の応募情報はすでに登録されています。応募情報表示ボタンで登録内容を表示してください。'
    }; // No.18
    @TestVisible
    private static final List<String> E_UPDATE_NOT_FOUND = new List<String>{ 'JUJ080-E004', '更新するレコードが存在しません。' }; // No.19
    // 【要確認】共通部品（checkOptimisticLock）の排他エラーと同じ文言にする
    @TestVisible
    private static final List<String> E_DETAIL_UPDATED = new List<String>{
        'JUJ080-E006',
        '他のユーザにより更新されています。再度表示してから操作してください。'
    }; // No.20
    @TestVisible
    private static final List<String> E_APPLICATION_NOT_FOUND = new List<String>{ 'WLP007-0008', '指定された応募情報は登録されていません。' }; // No.21
    @TestVisible
    private static final List<String> E_ASSIGNED = new List<String>{ 'WLP007-0006', 'すでに割当されているため削除できません。' }; // No.22

    // 割当フラグ（仮割当）・確定フラグの ON の値
    @TestVisible
    private static final String FLAG_ON = '1';

    @TestVisible
    private static final String REQUIRED_ON = '必須'; // 必須入力フラグ（ほかに「省略可」）
    @TestVisible
    private static final String OPTIONAL_OFF = '禁止'; // 任意入力フラグ（ほかに「許可」）

    // 共通部品の引数
    private static final String OBO_OBJECT_NAME = 'Juji_Jigyo_Oubo__c'; // 排他チェックの対象
    private static final Set<String> NO_CHECK_KEYS = new Set<String>(); // 一括割当実行中チェックの checkKeys（未使用）

    /**
     * 従事場所名・従事事業の取得（画面アクション No.2・No.18）
     * 戻り値：{ basyoName, jigyo: { jigyoName, shibuCode, shibuName, lastUketukeNo, inputControl } | null }
     */
    @AuraEnabled
    public static Map<String, Object> getJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        JigyoKey jigyoKey = toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo);
        JigyoResult result = new JigyoResult();
        if (String.isNotBlank(jigyoKey.jujiBasyoNo)) {
            Juji_Basyo_Master__c basyo = selectBasyo(jigyoKey.jujiBasyoNo);
            result.basyoName = basyo == null ? null : basyo.JujM_Juji_Basyo_Name__c;
        }
        Juji_Jigyo__c jigyo = selectJigyo(jigyoKey, false);
        if (jigyo != null) {
            result.jigyo = toJigyoInfo(jigyo);
        }
        return toMap(result);
    }

    /**
     * 従事者の取得（画面アクション No.19）
     * 戻り値：従事者情報部（取得できない場合は null。エラーとしない）
     */
    @AuraEnabled
    public static Map<String, Object> getJujisha(String jujishaNo) {
        return toMap(findJujisha(jujishaNo));
    }

    /**
     * 応募の読込（画面アクション No.7・No.8・No.20、5.データ更新 (1)）
     * 応募情報表示：従事事業キー＋登録番号/相談員番号で取得する（applicationId は null）
     * 応募情報検索からの戻り：applicationId で取得する
     * 戻り値：{ jigyoKey, jujishaNo, jujisha, application }（応募がない場合は application = null → 追加モード）
     */
    @AuraEnabled
    public static Map<String, Object> loadApplication(
        Id applicationId,
        String jujiJigyoNo,
        String jujiBasyoNo,
        String jisiNendo,
        String jujishaNo
    ) {
        try {
            LoadApplicationResult result = applicationId != null
                ? loadApplicationById(applicationId)
                : loadApplicationByJujisha(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), jujishaNo);
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // 応募情報表示
    private static LoadApplicationResult loadApplicationByJujisha(JigyoKey key, String jujishaNo) {
        // 従事事業の存在は画面でもチェック済み（サーバ側は防御用）
        Juji_Jigyo__c jigyo = selectJigyo(key, false);
        if (jigyo == null) {
            throw error(E_JIGYO_NOT_FOUND);
        }
        JujishaInfo jujisha = findJujisha(jujishaNo);
        if (jujisha == null) {
            throw error(E_JUJISHA_NOT_FOUND);
        }
        Juji_Jigyo_Oubo__c app = selectApplicationByJujisha(jigyo.Id, jujisha);
        LoadApplicationResult result = new LoadApplicationResult();
        result.jigyoKey = key;
        result.jujishaNo = jujishaNo;
        result.jujisha = jujisha;
        result.application = app == null ? null : toApplicationInfo(app);
        return result;
    }

    // 応募情報検索からの戻り（応募の従事事業キー・番号も返す）
    private static LoadApplicationResult loadApplicationById(Id applicationId) {
        Juji_Jigyo_Oubo__c app = selectApplicationById(applicationId);
        if (app == null) {
            throw error(E_APPLICATION_NOT_FOUND);
        }
        LoadApplicationResult result = new LoadApplicationResult();
        result.jigyoKey = toKey(
            app.Oubo_Juji_Jigyo__r.Juji_Juji_Jigyo_No__c,
            app.Oubo_Juji_Jigyo__r.Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c,
            app.Oubo_Juji_Jigyo__r.Juji_Jisi_Nendo__c
        );
        result.jujishaNo = app.Oubo_Kaiin__c != null
            ? app.Oubo_Kaiin__r.Kaii_Toroku_No__c
            : app.Oubo_Soudanin_Master__r.SouM_Sodanin_No__c;
        result.jujisha = findJujisha(result.jujishaNo);
        result.application = toApplicationInfo(app);
        return result;
    }

    /**
     * 従事事業の状態チェック（4.入力チェック No.14・No.15）
     * 従事可能日入力（checkJisshibi = true）：実施日の有無・一括割当実行中
     * 登録の確認前（checkJisshibi = false）：一括割当実行中（登録処理内でも再チェックする）
     */
    @AuraEnabled
    public static void checkJigyo(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, Boolean checkJisshibi) {
        try {
            // 従事事業の存在は画面でもチェック済み（サーバ側は防御用）
            Juji_Jigyo__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), false);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            if (checkJisshibi == true && !hasJisshibi(jigyo.Id)) {
                throw error(E_NO_JISSHIBI);
            }
            checkBulkAssigning(jigyo.Id);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    /**
     * 登録（画面アクション No.12、5.データ更新 (2) 追加モード・(3) 変更モード）
     * 引数：SaveRequest の JSON 文字列（applicationId が null の場合は追加モード）
     * 戻り値：{ uketukeNo }（採番しなかった場合は null）
     */
    @AuraEnabled
    public static Map<String, Object> saveApplication(String requestJson) {
        try {
            SaveRequest request = (SaveRequest) JSON.deserialize(requestJson, SaveRequest.class);
            Boolean isAdd = request.applicationId == null;

            // 従事事業をロックして取得する（受付番号の採番の重複を防ぐ）
            Juji_Jigyo__c jigyo = selectJigyo(request.jigyoKey, true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            checkBulkAssigning(jigyo.Id);
            JujishaInfo jujisha = findJujisha(request.jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }
            // 変更モードは応募をロックしてから取得する（応募明細の排他チェックから登録までの間に、明細が変更されないようにする）
            if (!isAdd) {
                lockApplication(jigyo.Id, jujisha);
            }
            Juji_Jigyo_Oubo__c existing = selectApplicationByJujisha(jigyo.Id, jujisha);
            if (isAdd && existing != null) {
                throw error(E_ALREADY_EXISTS);
            }
            if (!isAdd && existing == null) {
                throw error(E_UPDATE_NOT_FOUND);
            }
            if (!isAdd) {
                checkUpdated(existing.Id, request.systemModstamp);
                checkDetailsUpdated(existing.Oubo_Meisa_Juji_Jigyo_Oubo__r, request.meisaiVersion);
            }

            // 受付番号の採番：追加モード、または登録済みの受付番号が 0・未設定（マイページからの応募）の場合、最大値＋1
            Decimal uketukeNo = null;
            if (isAdd || existing.Oubo_Uketuke_No__c == null || existing.Oubo_Uketuke_No__c == 0) {
                uketukeNo = selectMaxUketukeNo(jigyo.Id) + 1;
            }

            Juji_Jigyo_Oubo__c rec;
            if (isAdd) {
                rec = new Juji_Jigyo_Oubo__c(Oubo_Juji_Jigyo__c = jigyo.Id);
                if (jujisha.jujishaType == TYPE_MEMBER) {
                    rec.Oubo_Kaiin__c = jujisha.recordId;
                } else {
                    rec.Oubo_Soudanin_Master__c = jujisha.recordId;
                }
            } else {
                // 変更モードでは従事事業・会員・相談員は更新しない
                rec = new Juji_Jigyo_Oubo__c(Id = existing.Id);
            }
            if (uketukeNo != null) {
                rec.Oubo_Uketuke_No__c = uketukeNo;
            }
            applyForm(rec, request.form);
            if (isAdd) {
                Database.insert(rec, AccessLevel.USER_MODE);
            } else {
                Database.update(rec, AccessLevel.USER_MODE);
            }

            // 従事事業応募明細：変更のあった時間帯のみ削除・登録する
            saveDetails(
                rec.Id,
                jigyo.Id,
                isAdd ? new List<Juji_Jigyo_Oubo_Meisai__c>() : existing.Oubo_Meisa_Juji_Jigyo_Oubo__r,
                request.kanoubiDates
            );

            // 採番した場合のみ返す（画面で最終受付番号に設定する）
            SaveResult result = new SaveResult();
            result.uketukeNo = uketukeNo;
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // 従事事業応募明細を画面の従事可能日に合わせる（5.データ更新 (3)④）
    // 時間帯（従事可能日・開始時間・終了時間）で照合し、画面で外した時間帯は削除、新たに選択した時間帯は登録する。
    // 変わらない時間帯はそのまま残す（同じ時間帯が重複して登録されている場合は1件のみ残す）
    private static void saveDetails(
        Id applicationId,
        Id jigyoId,
        List<Juji_Jigyo_Oubo_Meisai__c> currentList,
        List<KanoubiDate> kanoubiDates
    ) {
        Map<String, Juji_Jigyo_Oubo_Meisai__c> current = new Map<String, Juji_Jigyo_Oubo_Meisai__c>();
        List<Juji_Jigyo_Oubo_Meisai__c> deleteList = new List<Juji_Jigyo_Oubo_Meisai__c>();
        for (Juji_Jigyo_Oubo_Meisai__c detail : currentList) {
            String key = slotKey(detail.Oubo_Meisa_Juji_Kano_Nengapi__c, detail.Oubo_Meisai_Kaisi_Jikoku__c, detail.Oubo_Meisai_Syuryo_Jikoku__c);
            if (current.containsKey(key)) {
                deleteList.add(detail);
            } else {
                current.put(key, detail);
            }
        }

        Set<String> selectedKeys = new Set<String>();
        List<Juji_Jigyo_Oubo_Meisai__c> insertList = new List<Juji_Jigyo_Oubo_Meisai__c>();
        if (kanoubiDates != null) {
            for (KanoubiDate kanoubi : kanoubiDates) {
                // 時間帯が選択されていない日付は登録しない
                if (kanoubi.timeSlots == null) {
                    continue;
                }
                Date kanoubiDate = Date.valueOf(kanoubi.kanoubiDate);
                for (TimeSlot slot : kanoubi.timeSlots) {
                    Time startTime = toTime(slot.startTime);
                    Time endTime = toTime(slot.endTime);
                    String key = slotKey(kanoubiDate, startTime, endTime);
                    // 登録済みの時間帯、画面で重複している時間帯は登録しない
                    if (!selectedKeys.add(key) || current.containsKey(key)) {
                        continue;
                    }
                    insertList.add(
                        new Juji_Jigyo_Oubo_Meisai__c(
                            Oubo_Meisa_Juji_Jigyo_Oubo__c = applicationId,
                            Oubo_Meisa_Juji_Jigyo__c = jigyoId,
                            Oubo_Meisa_Juji_Kano_Nengapi__c = kanoubiDate,
                            Oubo_Meisai_Kaisi_Jikoku__c = startTime,
                            Oubo_Meisai_Syuryo_Jikoku__c = endTime
                        )
                    );
                }
            }
        }
        for (String key : current.keySet()) {
            if (!selectedKeys.contains(key)) {
                deleteList.add(current.get(key));
            }
        }

        if (!deleteList.isEmpty()) {
            Database.delete(deleteList, AccessLevel.USER_MODE);
        }
        if (!insertList.isEmpty()) {
            Database.insert(insertList, AccessLevel.USER_MODE);
        }
    }

    /**
     * 削除（画面アクション No.13、5.データ更新 (4)）
     * systemModstamp：応募読込時のシステム更新日時（排他チェック用）
     */
    @AuraEnabled
    public static void deleteApplication(
        String jujiJigyoNo,
        String jujiBasyoNo,
        String jisiNendo,
        String jujishaNo,
        Datetime systemModstamp
    ) {
        try {
            Juji_Jigyo__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            checkBulkAssigning(jigyo.Id);
            JujishaInfo jujisha = findJujisha(jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }
            Juji_Jigyo_Oubo__c app = selectApplicationByJujisha(jigyo.Id, jujisha);
            if (app == null) {
                throw error(E_APPLICATION_NOT_FOUND);
            }
            checkUpdated(app.Id, systemModstamp);
            if (hasAssignment(jigyo.Id, new List<Juji_Jigyo_Oubo__c>{ app })) {
                throw error(E_ASSIGNED);
            }
            // 従事事業応募明細は主従関係により同時に削除される
            Database.delete(new Juji_Jigyo_Oubo__c(Id = app.Id), AccessLevel.USER_MODE);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    /**
     * 全削除（画面アクション No.14、5.データ更新 (5)）
     * 1件でも割当がある場合はエラーとし、1件も削除しない。応募が0件の場合もエラーとしない
     */
    @AuraEnabled
    public static void deleteAllApplications(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        try {
            Juji_Jigyo__c jigyo = selectJigyo(toKey(jujiJigyoNo, jujiBasyoNo, jisiNendo), true);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            checkBulkAssigning(jigyo.Id);
            List<Juji_Jigyo_Oubo__c> apps = [
                SELECT Id, Oubo_Kaiin__c, Oubo_Soudanin_Master__c
                FROM Juji_Jigyo_Oubo__c
                WHERE Oubo_Juji_Jigyo__c = :jigyo.Id
                WITH USER_MODE
            ];
            if (apps.isEmpty()) {
                return;
            }
            if (hasAssignment(jigyo.Id, apps)) {
                throw error(E_ASSIGNED);
            }
            Database.delete(apps, AccessLevel.USER_MODE);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== Selector ====================
    private static Juji_Basyo_Master__c selectBasyo(String basyoNo) {
        List<Juji_Basyo_Master__c> recs = [
            SELECT Id, JujM_Juji_Basyo_Name__c
            FROM Juji_Basyo_Master__c
            WHERE JujM_Juji_Basyo_No__c = :basyoNo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事事業キーが揃っていない場合は null。forUpdate＝true の場合はロックする
    private static Juji_Jigyo__c selectJigyo(JigyoKey key, Boolean forUpdate) {
        if (key == null || !key.isComplete()) {
            return null;
        }
        String soql =
            'SELECT Id, Juji_Juji_Jigyo_Name__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Code__c, Juji_Jimusyo_Hojin__r.Jims_Sibu_Name__c,' +
            ' Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Yobi__c, Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Hi__c,' +
            ' Juji_Ouboji_Hisu_Nyuryoku_Flag_Kibo_Nisu__c, Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c,' +
            ' Juji_Ouboji_Nini_Nyuryoku_Flag_5Dankai__c, Juji_Ouboji_Nini_Nyuryoku_Flag_Skill_Tok__c,' +
            ' Juji_Ouboji_Nini_Nyuryoku_Flag_Tyosyo__c, Juji_Ouboji_Nini_Nyuryoku_Flag_Sodan__c' +
            ' FROM Juji_Jigyo__c' +
            ' WHERE Juji_Juji_Jigyo_No__c = :jigyoNo' +
            ' AND Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c = :basyoNo' +
            ' AND Juji_Jisi_Nendo__c = :nendo' +
            ' LIMIT 1' +
            (forUpdate ? ' FOR UPDATE' : '');
        Map<String, Object> binds = new Map<String, Object>{
            'jigyoNo' => key.jujiJigyoNo,
            'basyoNo' => key.jujiBasyoNo,
            'nendo' => key.jisiNendo
        };
        List<Juji_Jigyo__c> recs = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        return recs.isEmpty() ? null : recs[0];
    }

    // 受付番号の最大値（応募がない場合は 0）
    private static Decimal selectMaxUketukeNo(Id jigyoId) {
        List<AggregateResult> results = [
            SELECT MAX(Oubo_Uketuke_No__c) maxNo
            FROM Juji_Jigyo_Oubo__c
            WHERE Oubo_Juji_Jigyo__c = :jigyoId
            WITH USER_MODE
        ];
        Decimal maxNo = (Decimal) results[0].get('maxNo');
        return maxNo == null ? 0 : maxNo;
    }

    // 会員 → 相談員の順に取得する（取得できない場合は null）
    private static JujishaInfo findJujisha(String jujishaNo) {
        if (String.isBlank(jujishaNo)) {
            return null;
        }
        // 会員：支部コード・支部名は事務所・法人から、事務所住所・電話番号・FAX番号は会員から取得する
        List<Contact> members = [
            SELECT Id, Kaii_Toroku_No__c, Name, Kaii_Kaiin_Name_Furigana_Sei__c, Kaii_Kaiin_Name_Furigana_Mei__c,
                Account.Jims_Sibu_Code__c, Account.Jims_Sibu_Name__c,
                Kaii_Jimusyo_Syozaiti__c, Kaii_Jimusyo_Tel_No__c, Kaii_Jimusyo_Fax_No__c
            FROM Contact
            WHERE Kaii_Toroku_No__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!members.isEmpty()) {
            Contact m = members[0];
            JujishaInfo info = new JujishaInfo();
            info.jujishaType = TYPE_MEMBER;
            info.recordId = m.Id;
            info.jujishaNo = m.Kaii_Toroku_No__c;
            info.name = m.Name;
            info.furigana = joinName(m.Kaii_Kaiin_Name_Furigana_Sei__c, m.Kaii_Kaiin_Name_Furigana_Mei__c);
            info.shibuCode = m.Account?.Jims_Sibu_Code__c;
            info.shibuName = m.Account?.Jims_Sibu_Name__c;
            info.address = m.Kaii_Jimusyo_Syozaiti__c;
            info.tel = m.Kaii_Jimusyo_Tel_No__c;
            info.fax = m.Kaii_Jimusyo_Fax_No__c;
            return info;
        }
        // 相談員：支部コード・支部名は空白
        List<Soudanin_Master__c> sodanins = [
            SELECT Id, SouM_Sodanin_No__c, SouM_Sodanin_Name__c, SouM_Sodanin_Name_Furigana__c,
                SouM_Jimusyo_Jusyo__c, SouM_Jimusyo_Tel_No__c, SouM_Jimusyo_Fax_No__c
            FROM Soudanin_Master__c
            WHERE SouM_Sodanin_No__c = :jujishaNo
            WITH USER_MODE
            LIMIT 1
        ];
        if (!sodanins.isEmpty()) {
            Soudanin_Master__c s = sodanins[0];
            JujishaInfo info = new JujishaInfo();
            info.jujishaType = TYPE_SODANIN;
            info.recordId = s.Id;
            info.jujishaNo = s.SouM_Sodanin_No__c;
            info.name = s.SouM_Sodanin_Name__c;
            info.furigana = s.SouM_Sodanin_Name_Furigana__c;
            info.address = s.SouM_Jimusyo_Jusyo__c;
            info.tel = s.SouM_Jimusyo_Tel_No__c;
            info.fax = s.SouM_Jimusyo_Fax_No__c;
            return info;
        }
        return null;
    }

    private static Juji_Jigyo_Oubo__c selectApplicationById(Id applicationId) {
        if (applicationId == null) {
            return null;
        }
        List<Juji_Jigyo_Oubo__c> recs = Database.queryWithBinds(
            applicationSoql('Id = :applicationId'),
            new Map<String, Object>{ 'applicationId' => applicationId },
            AccessLevel.USER_MODE
        );
        return recs.isEmpty() ? null : recs[0];
    }

    private static Juji_Jigyo_Oubo__c selectApplicationByJujisha(Id jigyoId, JujishaInfo jujisha) {
        List<Juji_Jigyo_Oubo__c> recs = Database.queryWithBinds(
            applicationSoql(JUJISHA_CONDITION),
            jujishaBinds(jigyoId, jujisha),
            AccessLevel.USER_MODE
        );
        return recs.isEmpty() ? null : recs[0];
    }

    // 応募をロックする（応募明細を変更する処理も応募をロックするため、ロック中は他のユーザが明細を変更できない）
    // ※ FOR UPDATE はサブクエリ・ORDER BY と併用できないため、応募の取得とは別に行う
    private static void lockApplication(Id jigyoId, JujishaInfo jujisha) {
        Database.queryWithBinds(
            'SELECT Id FROM Juji_Jigyo_Oubo__c WHERE ' + JUJISHA_CONDITION + ' FOR UPDATE',
            jujishaBinds(jigyoId, jujisha),
            AccessLevel.USER_MODE
        );
    }

    // 従事事業・従事者が一致する応募の条件
    // 応募は会員・相談員のどちらか一方のみ設定されるため、もう一方は null で検索する
    private static final String JUJISHA_CONDITION =
        'Oubo_Juji_Jigyo__c = :jigyoId AND Oubo_Kaiin__c = :memberId AND Oubo_Soudanin_Master__c = :sodaninId';

    private static Map<String, Object> jujishaBinds(Id jigyoId, JujishaInfo jujisha) {
        return new Map<String, Object>{
            'jigyoId' => jigyoId,
            'memberId' => jujisha.jujishaType == TYPE_MEMBER ? jujisha.recordId : null,
            'sodaninId' => jujisha.jujishaType == TYPE_SODANIN ? jujisha.recordId : null
        };
    }

    // 従事事業応募と応募明細（従事可能日・開始時間の昇順）を取得する SOQL
    private static String applicationSoql(String whereClause) {
        List<String> fields = new List<String>{
            'Id',
            'Oubo_Uketuke_No__c',
            'SystemModstamp',
            'Oubo_Kaiin__c',
            'Oubo_Kaiin__r.Kaii_Toroku_No__c',
            'Oubo_Soudanin_Master__c',
            'Oubo_Soudanin_Master__r.SouM_Sodanin_No__c',
            'Oubo_Juji_Jigyo__r.Juji_Juji_Jigyo_No__c',
            'Oubo_Juji_Jigyo__r.Juji_Juji_Basyo_Master__r.JujM_Juji_Basyo_No__c',
            'Oubo_Juji_Jigyo__r.Juji_Jisi_Nendo__c',
            'Oubo_Renrakusaki_Kotei_No__c',
            'Oubo_Renrakusaki_Tel_No__c',
            'Oubo_Renrakusaki_Fax_No__c',
            'Oubo_Renrakusaki_Mail__c',
            'Oubo_Biko__c',
            'Oubo_Kibo_Juji_Nisu__c',
            'Oubo_Juji_Keiken__c',
            'Oubo_Skill_Toki_Jiko__c',
            'Oubo_Tyosyo_Ronbun__c',
            'Oubo_Sodan_Kamoku__c'
        };
        fields.addAll(WEEKDAY_FIELDS.values());
        fields.addAll(SKILL_FIELDS);
        return 'SELECT ' + String.join(fields, ', ') +
            ', (SELECT Id, Oubo_Meisa_Juji_Kano_Nengapi__c, Oubo_Meisai_Kaisi_Jikoku__c, Oubo_Meisai_Syuryo_Jikoku__c, SystemModstamp' +
            ' FROM Oubo_Meisa_Juji_Jigyo_Oubo__r ORDER BY Oubo_Meisa_Juji_Kano_Nengapi__c, Oubo_Meisai_Kaisi_Jikoku__c)' +
            ' FROM Juji_Jigyo_Oubo__c' +
            ' WHERE ' + whereClause +
            ' LIMIT 1';
    }

    // ==================== 変換 ====================
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

    // 内部クラス → Map（JSON 経由のため transient の項目は含まれない）
    @TestVisible
    private static Map<String, Object> toMap(Object dto) {
        if (dto == null) {
            return null;
        }
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto));
    }

    // 'HH:mm' → 時間型
    @TestVisible
    private static Time toTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        List<String> parts = value.split(':');
        return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 0, 0);
    }

    // 時間型 → 'HH:mm'（タイムゾーンの影響を受けないよう時・分から組み立てる）
    @TestVisible
    private static String toTimeText(Time value) {
        if (value == null) {
            return null;
        }
        return String.valueOf(value.hour()).leftPad(2, '0') + ':' + String.valueOf(value.minute()).leftPad(2, '0');
    }

    // 応募明細の照合キー（従事可能日＋開始時間＋終了時間。時間は時・分で比較する）
    private static String slotKey(Date kanoubiDate, Time startTime, Time endTime) {
        return String.valueOf(kanoubiDate) + ' ' + toTimeText(startTime) + '-' + toTimeText(endTime);
    }

    // 応募明細の版（件数＋システム更新日時の最大値）。読込後に他のユーザが明細を追加・削除・更新すると変わる
    @TestVisible
    private static String meisaiVersion(List<Juji_Jigyo_Oubo_Meisai__c> details) {
        Long latest = 0;
        for (Juji_Jigyo_Oubo_Meisai__c detail : details) {
            latest = Math.max(latest, detail.SystemModstamp.getTime());
        }
        return details.size() + '_' + latest;
    }

    private static JigyoInfo toJigyoInfo(Juji_Jigyo__c jigyo) {
        JigyoInfo info = new JigyoInfo();
        info.jigyoName = jigyo.Juji_Juji_Jigyo_Name__c;
        info.shibuCode = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Code__c;
        info.shibuName = jigyo.Juji_Jimusyo_Hojin__r?.Jims_Sibu_Name__c;
        // 最終受付番号：最大値が 0 または応募なしの場合は空白
        Decimal maxNo = selectMaxUketukeNo(jigyo.Id);
        info.lastUketukeNo = maxNo == 0 ? null : maxNo;
        info.inputControl = getInputControl(jigyo);
        return info;
    }

    private static ApplicationInfo toApplicationInfo(Juji_Jigyo_Oubo__c app) {
        ApplicationForm form = new ApplicationForm();
        form.telFixed = app.Oubo_Renrakusaki_Kotei_No__c;
        form.telMobile = app.Oubo_Renrakusaki_Tel_No__c;
        form.fax = app.Oubo_Renrakusaki_Fax_No__c;
        form.mail = app.Oubo_Renrakusaki_Mail__c;
        form.biko = app.Oubo_Biko__c;
        // 全日程従事可能は専用項目がないため、読込時は OFF とする【要確認 QA-17④】
        form.allDays = false;
        form.weekdays = new List<String>();
        for (String day : WEEKDAYS) {
            if (app.get(WEEKDAY_FIELDS.get(day)) == WEEKDAY_KA) {
                form.weekdays.add(day);
            }
        }
        form.kibouNissu = app.Oubo_Kibo_Juji_Nisu__c == null ? null : String.valueOf(app.Oubo_Kibo_Juji_Nisu__c);
        form.keiken = app.Oubo_Juji_Keiken__c;
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
        form.skillNote = app.Oubo_Skill_Toki_Jiko__c;
        form.chosho = app.Oubo_Tyosyo_Ronbun__c;
        form.sodanKamoku = app.Oubo_Sodan_Kamoku__c;

        ApplicationInfo info = new ApplicationInfo();
        info.applicationId = app.Id;
        info.uketukeNo = app.Oubo_Uketuke_No__c;
        info.systemModstamp = app.SystemModstamp; // 排他チェック用
        info.meisaiVersion = meisaiVersion(app.Oubo_Meisa_Juji_Jigyo_Oubo__r); // 応募明細の排他チェック用
        info.form = form;
        // 応募明細（1件＝1時間帯）を従事可能日ごとにまとめる
        info.kanoubiDates = new List<KanoubiDate>();
        Map<String, KanoubiDate> byDate = new Map<String, KanoubiDate>();
        for (Juji_Jigyo_Oubo_Meisai__c detail : app.Oubo_Meisa_Juji_Jigyo_Oubo__r) {
            String dateText = String.valueOf(detail.Oubo_Meisa_Juji_Kano_Nengapi__c);
            KanoubiDate kanoubi = byDate.get(dateText);
            if (kanoubi == null) {
                kanoubi = new KanoubiDate();
                kanoubi.kanoubiDate = dateText;
                kanoubi.timeSlots = new List<TimeSlot>();
                byDate.put(dateText, kanoubi);
                info.kanoubiDates.add(kanoubi);
            }
            TimeSlot slot = new TimeSlot();
            slot.startTime = toTimeText(detail.Oubo_Meisai_Kaisi_Jikoku__c);
            slot.endTime = toTimeText(detail.Oubo_Meisai_Syuryo_Jikoku__c);
            kanoubi.timeSlots.add(slot);
        }
        return info;
    }

    // 画面の入力値を従事事業応募に設定する
    private static void applyForm(Juji_Jigyo_Oubo__c rec, ApplicationForm form) {
        if (form == null) {
            form = new ApplicationForm();
        }
        rec.Oubo_Renrakusaki_Kotei_No__c = form.telFixed;
        rec.Oubo_Renrakusaki_Tel_No__c = form.telMobile;
        rec.Oubo_Renrakusaki_Fax_No__c = form.fax;
        rec.Oubo_Renrakusaki_Mail__c = form.mail;
        rec.Oubo_Biko__c = form.biko;
        // 従事可能曜日：選択＝「可」、未選択＝「不可」。全日程従事可能が ON の場合はすべて「可」
        // ※ Apex は大文字・小文字を区別しないため、定数 WEEKDAYS と同名（weekdays）の変数は使わないこと
        Set<String> selectedDays = form.weekdays == null ? new Set<String>() : new Set<String>(form.weekdays);
        for (String day : WEEKDAYS) {
            Boolean isKa = form.allDays == true || selectedDays.contains(day);
            rec.put(WEEKDAY_FIELDS.get(day), isKa ? WEEKDAY_KA : WEEKDAY_FUKA);
        }
        rec.Oubo_Kibo_Juji_Nisu__c = String.isBlank(form.kibouNissu) ? null : Decimal.valueOf(form.kibouNissu);
        rec.Oubo_Juji_Keiken__c = form.keiken;
        // スキル：SKILL_FIELDS の項目のみ設定し、未選択の科目は空とする
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
        rec.Oubo_Skill_Toki_Jiko__c = form.skillNote;
        rec.Oubo_Tyosyo_Ronbun__c = form.chosho;
        rec.Oubo_Sodan_Kamoku__c = form.sodanKamoku;
    }

    // 事業の必須入力フラグ・任意入力フラグ → 画面の入力制御
    // 未設定の場合は制限しない（必須入力フラグは「省略可」、任意入力フラグは「許可」として扱う）
    private static InputControl getInputControl(Juji_Jigyo__c jigyo) {
        InputControl ctrl = new InputControl();
        ctrl.requiredWeekday = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Yobi__c == REQUIRED_ON;
        ctrl.requiredKanoubi = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kano_Hi__c == REQUIRED_ON;
        ctrl.requiredKibouNissu = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_Kibo_Nisu__c == REQUIRED_ON;
        ctrl.requiredSkill = jigyo.Juji_Ouboji_Hisu_Nyuryoku_Flag_5Dankai__c == REQUIRED_ON;
        ctrl.optionalSkill = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_5Dankai__c != OPTIONAL_OFF;
        ctrl.optionalSkillNote = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_Skill_Tok__c != OPTIONAL_OFF;
        ctrl.optionalChosho = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_Tyosyo__c != OPTIONAL_OFF;
        ctrl.optionalSodanKamoku = jigyo.Juji_Ouboji_Nini_Nyuryoku_Flag_Sodan__c != OPTIONAL_OFF;
        return ctrl;
    }

    // 実施日（従事事業明細）が1件以上あるか
    private static Boolean hasJisshibi(Id jigyoId) {
        return [SELECT COUNT() FROM Juji_Jigyo_Meisai__c WHERE Juji_Meisai_Juji_Jigyo__c = :jigyoId WITH USER_MODE] > 0;
    }

    // ==================== 共通部品のチェック ====================
    // 一括割当実行中の場合はエラー
    private static void checkBulkAssigning(Id jigyoId) {
        Juj_CommonController.checkIkkatsuExecution(jigyoId, NO_CHECK_KEYS);
    }

    // 応募読込時から他のユーザにより更新されている場合はエラー
    // ※ 削除済みは検出されないため、呼出し前に応募の存在を確認すること
    private static void checkUpdated(Id applicationId, Datetime systemModstamp) {
        Juj_CommonController.checkOptimisticLock(new Map<Id, Datetime>{ applicationId => systemModstamp }, OBO_OBJECT_NAME);
    }

    // 応募読込時から他のユーザにより応募明細が追加・削除・更新されている場合はエラー（4.入力チェック No.20）
    // ※ 共通部品の排他チェックは明細の追加・削除を検出できないため、明細の版（件数＋最新のシステム更新日時）で判定する
    private static void checkDetailsUpdated(List<Juji_Jigyo_Oubo_Meisai__c> details, String clientVersion) {
        if (!meisaiVersion(details).equals(String.valueOf(clientVersion))) {
            throw error(E_DETAIL_UPDATED);
        }
    }

    // 応募の従事者に、同じ事業の割当（仮割当を含む）があるか
    // ※ 割当は応募を参照しないため、会員・相談員で照合する
    private static Boolean hasAssignment(Id jigyoId, List<Juji_Jigyo_Oubo__c> apps) {
        Set<Id> memberIds = new Set<Id>();
        Set<Id> sodaninIds = new Set<Id>();
        for (Juji_Jigyo_Oubo__c app : apps) {
            if (app.Oubo_Kaiin__c != null) {
                memberIds.add(app.Oubo_Kaiin__c);
            }
            if (app.Oubo_Soudanin_Master__c != null) {
                sodaninIds.add(app.Oubo_Soudanin_Master__c);
            }
        }
        if (memberIds.isEmpty() && sodaninIds.isEmpty()) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Juji_Jigyo_Wariate__c
            WHERE Wari_Juji_Jigyo__c = :jigyoId
            AND (Wari_Wriate_Flag__c = :FLAG_ON OR Wari_Kakutei_Flag__c = :FLAG_ON)
            AND (Wari_Kaiin__c IN :memberIds OR Wari_Soudanin_Master__c IN :sodaninIds)
            WITH USER_MODE
        ] > 0;
    }

    // ==================== 例外 ====================
    public class JujiOboException extends Exception {
        public String messageId;
    }

    private static JujiOboException error(List<String> msg) {
        JujiOboException e = new JujiOboException(msg[1]);
        e.messageId = msg[0];
        return e;
    }

    // setMessage しないと画面に文言が渡らない
    private static AuraHandledException toAuraException(JujiOboException e) {
        AuraHandledException ae = new AuraHandledException(e.getMessage());
        ae.setMessage(e.getMessage());
        return ae;
    }

    // ==================== DTO ====================
    public class JigyoKey {
        public String jujiJigyoNo;
        public String jujiBasyoNo;
        public String jisiNendo;

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
        // 会員ID または相談員ID（画面には返さない）
        public transient Id recordId;
    }

    public class LoadApplicationResult {
        public JigyoKey jigyoKey;
        public String jujishaNo;
        public JujishaInfo jujisha;
        public ApplicationInfo application;
    }

    public class ApplicationInfo {
        public Id applicationId;
        public Decimal uketukeNo;
        public Datetime systemModstamp;
        public String meisaiVersion; // 応募明細の版（排他チェック用）
        public ApplicationForm form;
        public List<KanoubiDate> kanoubiDates;
    }

    // 従事可能日（日付とその日に選択した時間帯）
    public class KanoubiDate {
        public String kanoubiDate; // 'yyyy-MM-dd'
        public List<TimeSlot> timeSlots;
    }

    public class TimeSlot {
        public String startTime; // 'HH:mm'
        public String endTime; // 'HH:mm'
    }

    public class ApplicationForm {
        public String telFixed;
        public String telMobile;
        public String fax;
        public String mail;
        public String biko;
        public Boolean allDays;
        public List<String> weekdays;
        public String kibouNissu;
        public String keiken; // 有／無
        public List<SkillValue> skills;
        public String skillNote;
        public String chosho;
        public String sodanKamoku;
    }

    public class SkillValue {
        public String field; // 項目の API 名
        public String value;
    }

    public class SaveRequest {
        public JigyoKey jigyoKey;
        public String jujishaNo;
        public Id applicationId;
        public Datetime systemModstamp;
        public String meisaiVersion; // 応募明細の版（排他チェック用）
        public ApplicationForm form;
        public List<KanoubiDate> kanoubiDates;
    }

    public class SaveResult {
        public Decimal uketukeNo;
    }
}
