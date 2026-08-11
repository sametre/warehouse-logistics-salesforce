public with sharing class WarehouseTransactionManager {
    public class Scope {
        private Savepoint checkpoint;
        private Boolean active = true;

        public Scope() {
            checkpoint = Database.setSavepoint();
        }

        public void complete() {
            if (!active) {
                return;
            }
            Database.releaseSavepoint(checkpoint);
            active = false;
        }

        public void rollback() {
            if (!active) {
                return;
            }
            Database.rollback(checkpoint);
            Database.releaseSavepoint(checkpoint);
            active = false;
        }
    }

    public static Scope begin() {
        return new Scope();
    }
}
