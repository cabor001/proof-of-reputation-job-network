import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "User can create profile successfully",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("john_doe"),
                types.list([types.ascii("javascript"), types.ascii("python")])
            ], user1.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
        
        // Verify profile was created
        let profile = chain.callReadOnlyFn(
            'proof-of-reputation-job-network',
            'get-user-profile',
            [types.principal(user1.address)],
            deployer.address
        );
        
        const profileData = profile.result.expectSome().expectTuple();
        assertEquals(profileData['username'], types.ascii("john_doe"));
        assertEquals(profileData['reputation-score'], types.uint(100));
    },
});

Clarinet.test({
    name: "User cannot create duplicate profile",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("john_doe"),
                types.list([types.ascii("javascript")])
            ], user1.address),
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("jane_doe"),
                types.list([types.ascii("python")])
            ], user1.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectErr().expectUint(102); // err-unauthorized
    },
});

Clarinet.test({
    name: "Employer can post job successfully",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const employer = accounts.get('wallet_1')!;
        
        // Create employer profile first
        let setupBlock = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("employer1"),
                types.list([types.ascii("management")])
            ], employer.address)
        ]);
        
        let block = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'post-job', [
                types.ascii("Web Developer Needed"),
                types.ascii("Looking for an experienced web developer"),
                types.uint(1000),
                types.uint(80),
                types.list([types.ascii("javascript"), types.ascii("react")]),
                types.uint(1000) // deadline
            ], employer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    },
});

Clarinet.test({
    name: "User can apply for job with sufficient reputation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const employer = accounts.get('wallet_1')!;
        const freelancer = accounts.get('wallet_2')!;
        
        // Setup profiles and job
        let setupBlock = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("employer1"),
                types.list([types.ascii("management")])
            ], employer.address),
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("freelancer1"),
                types.list([types.ascii("javascript"), types.ascii("react")])
            ], freelancer.address),
            Tx.contractCall('proof-of-reputation-job-network', 'post-job', [
                types.ascii("Web Developer Needed"),
                types.ascii("Looking for an experienced web developer"),
                types.uint(1000),
                types.uint(50), // Required reputation (freelancer has 100)
                types.list([types.ascii("javascript"), types.ascii("react")]),
                types.uint(1000)
            ], employer.address)
        ]);
        
        let block = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'apply-for-job', [
                types.uint(1),
                types.ascii("I am experienced in React and JavaScript"),
                types.uint(900),
                types.uint(7)
            ], freelancer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
    },
});

Clarinet.test({
    name: "User cannot apply for job with insufficient reputation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const employer = accounts.get('wallet_1')!;
        const freelancer = accounts.get('wallet_2')!;
        
        // Setup profiles and job
        let setupBlock = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("employer1"),
                types.list([types.ascii("management")])
            ], employer.address),
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("freelancer1"),
                types.list([types.ascii("javascript")])
            ], freelancer.address),
            Tx.contractCall('proof-of-reputation-job-network', 'post-job', [
                types.ascii("Senior Developer Needed"),
                types.ascii("Looking for a senior developer"),
                types.uint(2000),
                types.uint(150), // Required reputation (freelancer has 100)
                types.list([types.ascii("javascript"), types.ascii("react")]),
                types.uint(1000)
            ], employer.address)
        ]);
        
        let block = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'apply-for-job', [
                types.uint(1),
                types.ascii("I would like to work on this project"),
                types.uint(1800),
                types.uint(10)
            ], freelancer.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(106); // err-insufficient-reputation
    },
});

Clarinet.test({
    name: "Employer can assign job to freelancer",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const employer = accounts.get('wallet_1')!;
        const freelancer = accounts.get('wallet_2')!;
        
        // Setup and apply for job
        let setupBlock = chain.mineBlock([
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("employer1"),
                types.list([types.ascii("management")])
            ], employer.address),
            Tx.contractCall('proof-of-reputation-job-network', 'create-user-profile', [
                types.ascii("freelancer1"),
                types.list([types.ascii("javascript")])
            ], freelancer.address),
            Tx.contractCall('proof-of-reputation-job-network', 'post-job', [
                types.ascii("Web Developer Needed"),
                types.ascii("Looking for an experienced web developer"),