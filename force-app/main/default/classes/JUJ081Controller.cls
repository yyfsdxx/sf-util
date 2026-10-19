/**
 * JUJ081 従事可能日指定 コントローラ
 * 設計書：JUJ081 従事可能日指定 処理詳細 v5（2026/10/16 時間帯対応）
 *
 * ※ 本画面は DB を更新しない（参照のみ）。選択結果は JUJ080 へ返却し、JUJ080 の登録時に登録する。
 * ※ オブジェクト名・項目名は論理名で記載している（API 名確定後に一括置換する）。
 * ※ SOQL はすべてユーザモードで実行し、支部の条件は付けない。
 * ※ 画面から受け取った Id は使用せず、従事事業キー・番号から都度取得する。
 * ※ LWC から呼び出すメソッドは内部クラスを引数・戻り値に使用できないため、
 *   引数は基本型、戻り値は Map／List<Map> とする。
 */
public with sharing class JUJ081Controller {

    // ==================== 定数 ====================
    // 【要確認 QA-20】メッセージ（{メッセージID, 文言}）
    @TestVisible
    private static final List<String> E_JIGYO_NOT_FOUND = new List<String>{ 'JUJ081-E001', '従事事業が存在しません。' };
    @TestVisible
    private static final List<String> E_JUJISHA_NOT_FOUND = new List<String>{ 'WLP007-0009', '従事者が存在しません。' };
    @TestVisible
    private static final List<String> E_BULK_ASSIGNING = new List<String>{ 'WLP009-0008', '一括割当実行中のため処理できません。' };

    private static final String TIME_FORMAT = 'HH:mm';

    // 割当のフラグ項目（割当フラグ・確定フラグ）は選択リスト。値 '1' で ON（仮割当・確定）
    @TestVisible
    private static final String FLAG_ON = '1';

    // ==================== 1. 初期表示 ====================
    // 戻り値：{ jigyo: { jigyoName, shibuCode, shibuName, basyoName }, jujishaName,
    //          ownAssigned: [{ kanoubiDate, timeSlots: [{ startTime, endTime }] }],
    //          minJisshibi: 'yyyy-MM-dd' | null, maxJisshibi: 'yyyy-MM-dd' | null }
    @AuraEnabled
    public static Map<String, Object> init(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, String jujishaNo) {
        try {
            // (2)① 従事事業の取得。取得できない場合はエラー
            従事事業__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            // (2)② 従事者の取得。取得できない場合はエラー
            Jujisha jujisha = findJujisha(jujishaNo);
            if (jujisha == null) {
                throw error(E_JUJISHA_NOT_FOUND);
            }

            InitResult result = new InitResult();
            result.jigyo = new JigyoInfo();
            result.jigyo.jigyoName = jigyo.従事事業名__c;
            result.jigyo.shibuCode = jigyo.支部__r?.支部コード__c;
            result.jigyo.shibuName = jigyo.支部__r?.Name;
            result.jigyo.basyoName = jigyo.従事場所__r?.従事場所名__c;
            result.jujishaName = jujisha.name;

            // (2)③ 本人割当済の時間帯
            result.ownAssigned = selectOwnAssignments(jigyo.Id, jujisha);

            // (3)① 実施日の範囲（最も早い実施日・最も遅い実施日）。実施日がない場合は null
            AggregateResult agg = [
                SELECT MIN(実施日__c) minDate, MAX(実施日__c) maxDate
                FROM 従事事業明細__c
                WHERE 従事事業__c = :jigyo.Id
                WITH USER_MODE
            ];
            result.minJisshibi = toDateText((Date) agg.get('minDate'));
            result.maxJisshibi = toDateText((Date) agg.get('maxDate'));
            return toMap(result);
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 4.(1) 一覧の表示 ====================
    // 引数：fromDate・toDate（'yyyy-MM-dd'。表示期間の開始日・終了日）
    // 戻り値：表示期間内の実施日のリスト
    //   [{ jisshibi, boshuNinzu, startTime, endTime, biko, wariateNinzu,
    //      timeSlots: [{ startTime, endTime, count, wariateNinzu }] }]
    @AuraEnabled
    public static List<Map<String, Object>> getDays(
        String jujiJigyoNo, String jujiBasyoNo, String jisiNendo, String fromDate, String toDate
    ) {
        try {
            従事事業__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            Date fromD = Date.valueOf(fromDate);
            Date toD = Date.valueOf(toDate);

            // ③ 実施日
            List<従事事業明細__c> recs = [
                SELECT 実施日__c, 募集人数__c, 開始時間__c, 終了時間__c, 備考__c, 時間帯__c
                FROM 従事事業明細__c
                WHERE 従事事業__c = :jigyo.Id
                AND 実施日__c >= :fromD
                AND 実施日__c <= :toD
                WITH USER_MODE
                ORDER BY 実施日__c
            ];

            // ⑤ 確定した割当（日付ごと）
            Map<Date, List<Assignment>> assignments = selectConfirmedAssignments(jigyo.Id, fromD, toD);

            List<Map<String, Object>> days = new List<Map<String, Object>>();
            for (従事事業明細__c rec : recs) {
                List<Assignment> dayAssignments = assignments.containsKey(rec.実施日__c)
                    ? assignments.get(rec.実施日__c)
                    : new List<Assignment>();
                DayInfo day = new DayInfo();
                day.jisshibi = toDateText(rec.実施日__c);
                day.boshuNinzu = rec.募集人数__c;
                day.startTime = toTimeText(rec.開始時間__c);
                day.endTime = toTimeText(rec.終了時間__c);
                day.biko = rec.備考__c;
                // a. 日付行：その日の割当の件数
                day.wariateNinzu = dayAssignments.size();
                // ④ 時間帯行（開始時間の昇順）。b. 割当人数：その時間帯を含む割当の件数
                day.timeSlots = new List<SlotInfo>();
                for (SlotInfo slot : sortSlots(parseSlots(rec.時間帯__c))) {
                    slot.wariateNinzu = 0;
                    for (Assignment a : dayAssignments) {
                        if (a.slotKeys.contains(slotKey(slot.startTime, slot.endTime))) {
                            slot.wariateNinzu++;
                        }
                    }
                    day.timeSlots.add(slot);
                }
                days.add(toMap(day));
            }
            return days;
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== 3.(1) 保存ボタン押下時の入力チェック ====================
    // 一括割当実行中の場合はエラー
    @AuraEnabled
    public static void checkSave(String jujiJigyoNo, String jujiBasyoNo, String jisiNendo) {
        try {
            従事事業__c jigyo = selectJigyo(jujiJigyoNo, jujiBasyoNo, jisiNendo);
            if (jigyo == null) {
                throw error(E_JIGYO_NOT_FOUND);
            }
            if (isBulkAssigning(jigyo.Id)) {
                throw error(E_BULK_ASSIGNING);
            }
        } catch (JujiOboException e) {
            throw toAuraException(e);
        }
    }

    // ==================== Selector ====================
    // 従事事業（3項目のいずれかが未入力の場合はクエリを発行しない）
    private static 従事事業__c selectJigyo(String jigyoNo, String basyoNo, String nendo) {
        if (String.isBlank(jigyoNo) || String.isBlank(basyoNo) || String.isBlank(nendo)) {
            return null;
        }
        List<従事事業__c> recs = [
            SELECT Id, 従事事業名__c, 支部__r.支部コード__c, 支部__r.Name, 従事場所__r.従事場所名__c
            FROM 従事事業__c
            WHERE 従事事業No__c = :jigyoNo
            AND 従事場所__r.従事場所No__c = :basyoNo
            AND 実施年度__c = :nendo
            WITH USER_MODE
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // 従事者（会員 → 相談員の順に取得。取得できない場合は null）
    private static Jujisha findJujisha(String jujishaNo) {
        if (String.isBlank(jujishaNo)) {
            return null;
        }
        List<Contact> members = [
            SELECT Id, Name FROM Contact WHERE 登録番号__c = :jujishaNo WITH USER_MODE LIMIT 1
        ];
        if (!members.isEmpty()) {
            Jujisha j = new Jujisha();
            j.memberId = members[0].Id;
            j.name = members[0].Name;
            return j;
        }
        List<相談員__c> sodanins = [
            SELECT Id, 氏名__c FROM 相談員__c WHERE 相談員番号__c = :jujishaNo WITH USER_MODE LIMIT 1
        ];
        if (!sodanins.isEmpty()) {
            Jujisha j = new Jujisha();
            j.sodaninId = sodanins[0].Id;
            j.name = sodanins[0].氏名__c;
            return j;
        }
        return null;
    }

    // ==================== 割当（従事事業割当）====================
    // ※ 1件＝ある日に1人を割り当てたもの。従事事業の主従子オブジェクトで、会員・相談員を参照する。
    //   仮割当＝割当フラグ＝1、確定＝確定フラグ＝1。時間帯項目に従事する時間帯を JSON で保持する。

    // 1.(2)③ 本人の割当（仮割当を含む）の時間帯（日付ごと）
    @TestVisible
    private static List<KanoubiDate> selectOwnAssignments(Id jigyoId, Jujisha jujisha) {
        Id memberId = jujisha.memberId;
        Id sodaninId = jujisha.sodaninId;
        List<従事事業割当__c> recs = [
            SELECT 従事日__c, 時間帯__c
            FROM 従事事業割当__c
            WHERE 従事事業__c = :jigyoId
            AND 会員__c = :memberId
            AND 相談員__c = :sodaninId
            AND (割当フラグ__c = :FLAG_ON OR 確定フラグ__c = :FLAG_ON)
            WITH USER_MODE
            ORDER BY 従事日__c
        ];
        // 同じ日に複数件ある場合は時間帯をまとめる
        Map<Date, Set<String>> keysByDate = new Map<Date, Set<String>>();
        for (従事事業割当__c rec : recs) {
            if (!keysByDate.containsKey(rec.従事日__c)) {
                keysByDate.put(rec.従事日__c, new Set<String>());
            }
            for (SlotInfo slot : parseSlots(rec.時間帯__c)) {
                keysByDate.get(rec.従事日__c).add(slotKey(slot.startTime, slot.endTime));
            }
        }
        List<KanoubiDate> result = new List<KanoubiDate>();
        for (Date d : keysByDate.keySet()) {
            KanoubiDate k = new KanoubiDate();
            k.kanoubiDate = toDateText(d);
            k.timeSlots = new List<TimeSlotKey>();
            for (String key : keysByDate.get(d)) {
                TimeSlotKey slot = new TimeSlotKey();
                slot.startTime = key.substringBefore('-');
                slot.endTime = key.substringAfter('-');
                k.timeSlots.add(slot);
            }
            result.add(k);
        }
        return result;
    }

    // 4.(1)⑤ 表示期間内の確定した割当（日付ごと）
    @TestVisible
    private static Map<Date, List<Assignment>> selectConfirmedAssignments(Id jigyoId, Date fromD, Date toD) {
        Map<Date, List<Assignment>> result = new Map<Date, List<Assignment>>();
        for (従事事業割当__c rec : [
            SELECT 従事日__c, 時間帯__c
            FROM 従事事業割当__c
            WHERE 従事事業__c = :jigyoId
            AND 従事日__c >= :fromD
            AND 従事日__c <= :toD
            AND 確定フラグ__c = :FLAG_ON
            WITH USER_MODE
        ]) {
            Assignment a = new Assignment();
            for (SlotInfo slot : parseSlots(rec.時間帯__c)) {
                a.slotKeys.add(slotKey(slot.startTime, slot.endTime));
            }
            if (!result.containsKey(rec.従事日__c)) {
                result.put(rec.従事日__c, new List<Assignment>());
            }
            result.get(rec.従事日__c).add(a);
        }
        return result;
    }

    // ==================== Gateway ====================
    // 【要確認 QA-15】一括割当実行中か。共通チェック提供までは常に false
    @TestVisible
    private static Boolean isBulkAssigning(Id jigyoId) {
        return false;
    }

    // ==================== 変換 ====================
    // 時間帯 JSON → 時間帯リスト（未設定・形式不正の場合は空。使用しない項目は無視する）
    @TestVisible
    private static List<SlotInfo> parseSlots(String value) {
        if (String.isBlank(value)) {
            return new List<SlotInfo>();
        }
        try {
            return (List<SlotInfo>) JSON.deserialize(value, List<SlotInfo>.class);
        } catch (JSONException e) {
            return new List<SlotInfo>();
        }
    }

    // 開始時間の昇順に並べる（'HH:mm' の文字列比較）
    private static List<SlotInfo> sortSlots(List<SlotInfo> slots) {
        List<String> keys = new List<String>();
        Map<String, SlotInfo> byKey = new Map<String, SlotInfo>();
        for (Integer i = 0; i < slots.size(); i++) {
            String k = slots[i].startTime + '|' + slots[i].endTime + '|' + String.valueOf(i).leftPad(4, '0');
            keys.add(k);
            byKey.put(k, slots[i]);
        }
        keys.sort();
        List<SlotInfo> sorted = new List<SlotInfo>();
        for (String k : keys) {
            sorted.add(byKey.get(k));
        }
        return sorted;
    }

    // 時間帯の同一判定キー（開始時間＋終了時間）
    @TestVisible
    private static String slotKey(String startTime, String endTime) {
        return startTime + '-' + endTime;
    }

    private static String toDateText(Date d) {
        return d == null ? null : String.valueOf(d); // 'yyyy-MM-dd'
    }

    // 【要確認】開始時間・終了時間の型（時間型・テキスト型のいずれでも 'HH:mm' にする）
    @TestVisible
    private static String toTimeText(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Time) {
            Time t = (Time) value;
            return Datetime.newInstance(Date.today(), t).format(TIME_FORMAT);
        }
        return String.valueOf(value);
    }

    private static Map<String, Object> toMap(Object dto) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto));
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

    private static AuraHandledException toAuraException(JujiOboException e) {
        AuraHandledException ae = new AuraHandledException(e.getMessage());
        ae.setMessage(e.getMessage());
        return ae;
    }

    // ==================== DTO（クラス内部でのみ使用） ====================
    public class InitResult {
        public JigyoInfo jigyo;
        public String jujishaName;
        public List<KanoubiDate> ownAssigned;
        public String minJisshibi;
        public String maxJisshibi;
    }

    public class JigyoInfo {
        public String jigyoName;
        public String shibuCode;
        public String shibuName;
        public String basyoName;
    }

    // 従事者（サーバ内部でのみ使用）
    public class Jujisha {
        public Id memberId;
        public Id sodaninId;
        public String name;
    }

    // 実施日（日付行）
    public class DayInfo {
        public String jisshibi; // 'yyyy-MM-dd'
        public Decimal boshuNinzu;
        public String startTime;
        public String endTime;
        public String biko;
        public Integer wariateNinzu;
        public List<SlotInfo> timeSlots;
    }

    // 時間帯（従事事業明細の時間帯項目の1要素。count＝募集人数）
    public class SlotInfo {
        public String startTime;
        public String endTime;
        public Integer count;
        public Integer wariateNinzu;
    }

    // 従事可能日（日付と時間帯）
    public class KanoubiDate {
        public String kanoubiDate;
        public List<TimeSlotKey> timeSlots;
    }

    public class TimeSlotKey {
        public String startTime;
        public String endTime;
    }

    // 割当（1件＝ある日に1人。slotKeys は実施時間帯明細の時間帯キー）
    public class Assignment {
        public Set<String> slotKeys = new Set<String>();
    }
}
