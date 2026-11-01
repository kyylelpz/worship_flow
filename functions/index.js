import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { createFoundationService } from './foundation.js';

initializeApp();
const service = createFoundationService(getFirestore());
// Verified Google identity is checked again inside every service operation.
// App Check is not enforced until clients are provisioned for it.
const options = { region: 'asia-east2', maxInstances: 10, timeoutSeconds: 30 };
export const ensureAccount = onCall(options, request => service.ensureAccount(request.auth));
export const completeProfile = onCall(options, request => service.completeProfile(request.auth, request.data));
export const getPrivateInvitationCode = onCall(options, request => service.getPrivateInvitationCode(request.auth));
export const createGroup = onCall(options, request => service.createGroup(request.auth, request.data));
